# frozen_string_literal: true

# Deterministic graders for eval v0. Each reads its hidden reference data from
# evals/hidden/<task> only at grading time, after the model run has finished.

require "json"
require "open3"
require "yaml"

module Evals
  module Graders
    module_function

    # The last fenced ```json block in the reply, else nil.
    def json_block(text)
      blocks = text.to_s.scan(/```json\s*\n(.*?)```/m).flatten
      return nil if blocks.empty?
      JSON.parse(blocks.last)
    rescue JSON::ParserError
      nil
    end

    def norm_path(path, workspace)
      p = path.to_s.strip.sub(%r{\A\./}, "")
      ws = File.realpath(workspace) rescue workspace
      [ws, workspace].each { |w| p = p.delete_prefix("#{w}/") }
      p
    end

    def lines_around(file, line, tol)
      return [] unless File.file?(file)
      all = File.readlines(file)
      from = [line.to_i - tol - 1, 0].max
      all[from, 2 * tol + 1] || []
    end

    # ---------------------------------------------------------------- explore

    def explore(task, final_text, workspace)
      ref = YAML.safe_load(File.read(File.join(task.hidden_dir, "expected.yaml")))
      data = json_block(final_text)
      return { "pass" => false, "format_ok" => false, "reason" => "no parseable JSON block" } unless data.is_a?(Hash)
      findings = Array(data["findings"]).select { |f| f.is_a?(Hash) }
      tol = ref["line_tolerance"].to_i
      pattern = Regexp.new(ref["support_pattern"])
      matched = {}
      fps = []
      acceptable_hits = []
      details = findings.map do |f|
        path = norm_path(f["path"], workspace)
        full = File.join(workspace, path)
        exists = File.file?(full)
        supported = if !exists then false
                    elsif ref["match"] == "line" && f["line"] then lines_around(full, f["line"], tol).any? { |l| l =~ pattern }
                    else File.read(full) =~ pattern ? true : false
                    end
        hit = Array(ref["expected"]).find do |e|
          e["path"] == path && (ref["match"] != "line" || (f["line"] && (f["line"].to_i - e["line"].to_i).abs <= tol))
        end
        if hit
          matched[hit["id"]] = true
        elsif Array(ref["acceptable"]).include?(path)
          acceptable_hits << path
        else
          fps << path
        end
        { "path" => path, "line" => f["line"], "exists" => exists, "supported" => supported, "match" => hit&.fetch("id") }
      end
      expected = Array(ref["expected"]).size
      tp = matched.size
      precision = tp + fps.size > 0 ? (tp.to_f / (tp + fps.size)).round(3) : nil
      {
        "pass" => tp == expected && fps.empty?, "format_ok" => true,
        "recall" => (tp.to_f / expected).round(3), "precision" => precision,
        "true_positives" => tp, "expected" => expected, "false_positives" => fps, "acceptable_extras" => acceptable_hits,
        "cited_paths_exist" => details.count { |d| d["exists"] }, "cited_supported" => details.count { |d| d["supported"] },
        "findings" => details.size, "detail" => details
      }
    end

    # ---------------------------------------------------------------- implementation

    # Changed paths versus the base commit, including untracked files.
    def workspace_changes(workspace)
      out, st = Open3.capture2("git", "-C", workspace, "status", "--porcelain", "--untracked-files=all", "--ignored")
      return [] unless st.success?
      out.lines.map { |l| l[3..].to_s.strip.split(" -> ").last }.reject(&:empty?).sort
    end

    # Passing needs every hidden test AND no changes outside the owned files
    # (left-behind test skills count as unrelated changes).
    def impl(task, _final_text, workspace)
      load File.join(task.hidden_dir, "tests.rb")
      results = ImplNewSkillTests.run(workspace)
      passed = results.count { |_, r| r["pass"] }
      unrelated = workspace_changes(workspace).reject { |p| task.owned.include?(p) }
      { "pass" => passed == results.size && unrelated.empty?, "tests_passed" => passed, "tests_total" => results.size,
        "unrelated_paths" => unrelated, "ownership_ok" => unrelated.empty?, "tests" => results }
    end

    # ---------------------------------------------------------------- review

    # grade-v3. Every finding gets exactly one class, tried in this order:
    #   defect             first finding credited to a seeded defect
    #   duplicate          a tool-reported (mechanical) issue repeated, a second
    #                      finding for an already credited defect, or a listed
    #                      restatement of a defect's consequence
    #   valid_blocking     a real defect other than the seeded one, verified
    #                      against the revision (`other_blocking`); a reviewer who
    #                      blocks on it is right to
    #   incorrect          a claim verified false against the reviewed revision
    #   process_note       a statement about the review itself, not the code
    #   valid_out_of_scope true of the revision but not a seeded defect
    #   unclassified       none of the above; needs human adjudication
    # Only `incorrect` counts as a false positive. A task with no defects is a
    # control. A run passes when it finds every critical seeded defect and its
    # verdict is the expected one, or is CHANGES_REQUESTED resting on a
    # valid_blocking finding it marked blocking, and no blocking finding of
    # its own is verified incorrect.
    def review(task, final_text, _workspace)
      ref = YAML.safe_load(File.read(File.join(task.hidden_dir, "defects.yaml")))
      data = json_block(final_text)
      return { "pass" => false, "format_ok" => false, "reason" => "no parseable JSON block" } unless data.is_a?(Hash)
      tol = ref["line_tolerance"].to_i
      defects = Array(ref["defects"])
      findings = Array(data["findings"]).select { |f| f.is_a?(Hash) }
      text_of = ->(f) { [f["summary"], f["requirement"]].compact.join(" ") }
      kw = ->(f, x) { text_of.call(f) =~ /#{x['keywords']}/i }
      # Line credit needs a line inside the entry's range (the packet asks for
      # one); an entry may set its own tolerance and the file it applies to.
      placed = lambda do |f, x|
        next false unless x["path"].nil? || f["path"].to_s.end_with?(x["path"])
        next true unless x["lines"]
        t = (x["tolerance"] || tol).to_i
        f["line"].is_a?(Integer) && f["line"].between?(x["lines"][0] - t, x["lines"][1] + t)
      end
      # An entry may also apply only to findings of one severity.
      sev_ok = ->(f, x) { x["severity"].nil? || f["severity"].to_s.downcase == x["severity"] }
      pick = ->(f, list) { Array(ref[list]).find { |x| kw.call(f, x) && placed.call(f, x) && sev_ok.call(f, x) } }
      # Human adjudications (hidden/<task>/adjudications.yaml): the exact text
      # of a finding, the class a reader gave it against the code, and why.
      # They are applied before the keyword rules.
      adj_file = File.join(task.hidden_dir, "adjudications.yaml")
      adjudications = File.file?(adj_file) ? Array(YAML.safe_load(File.read(adj_file))) : []
      by_id = ->(list, id) { Array(ref[list]).find { |x| x["id"] == id } }
      credited = {}
      classified = findings.map do |f|
        ruling = adjudications.find { |a| a["summary"].to_s.strip == f["summary"].to_s.strip }
        if ruling
          d = ruling["class"] == "defect" ? defects.find { |x| x["id"] == ruling["id"] } : nil
          klass = d && credited[d["id"]] ? "duplicate" : ruling["class"]
          credited[d["id"]] ||= f if d
          next { "finding" => f, "class" => klass, "adjudicated" => true, "defect" => d&.fetch("id"),
                 "other_blocking" => (ruling["id"] if ruling["class"] == "valid_blocking" && by_id.call("other_blocking", ruling["id"])),
                 "acceptable" => (ruling["id"] if ruling["class"] == "valid_out_of_scope") }.compact
        end
        d = defects.find { |x| kw.call(f, x) && placed.call(f, x) }
        m = d ? nil : pick.call(f, "mechanical")
        r = d || m ? nil : pick.call(f, "restatements")
        other = d || m || r ? nil : pick.call(f, "other_blocking")
        rest = d || m || r || other
        inc = rest ? nil : pick.call(f, "incorrect")
        note = rest || inc ? nil : pick.call(f, "process_notes")
        acc = rest || inc || note ? nil : pick.call(f, "acceptable")
        klass, kind = if d && !credited[d["id"]] then ["defect", nil]
                      elsif d then ["duplicate", "repeated_defect"]
                      elsif m then ["duplicate", "tool_reported"]
                      elsif r then ["duplicate", "restates_#{r['of']}"]
                      elsif other then ["valid_blocking", nil]
                      elsif inc then ["incorrect", nil]
                      elsif note then ["process_note", nil]
                      elsif acc then ["valid_out_of_scope", nil]
                      else ["unclassified", nil]
                      end
        credited[d["id"]] ||= f if d
        { "finding" => f, "class" => klass, "duplicate_kind" => kind, "defect" => d&.fetch("id"), "mechanical" => m&.fetch("id"),
          "restatement" => r&.fetch("id"), "other_blocking" => other&.fetch("id"), "incorrect" => inc&.fetch("id"), "process_note" => note&.fetch("id"),
          "acceptable" => acc&.fetch("id") }.compact
      end
      count = ->(k) { classified.count { |c| c["class"] == k } }
      found = credited.keys
      critical = defects.select { |d| d["critical"] }.map { |d| d["id"] }
      spec_refs = defects.select { |d| d["axis"] == "SPEC" && found.include?(d["id"]) }.to_h do |d|
        fs = classified.select { |c| c["defect"] == d["id"] }.map { |c| c["finding"] }
        [d["id"], fs.any? { |f| f["axis"].to_s.upcase == "SPEC" && f["requirement"].to_s.include?(d["requirement"]) }]
      end
      standards_axis = defects.select { |d| d["axis"] == "STANDARDS" && found.include?(d["id"]) }.to_h do |d|
        [d["id"], classified.any? { |c| c["defect"] == d["id"] && c["finding"]["axis"].to_s.upcase == "STANDARDS" }]
      end
      blocking_other = classified.select { |c| c["class"] != "defect" && c["defect"].nil? && c["finding"]["severity"].to_s.downcase == "blocking" }
      verdict = data["verdict"].to_s.upcase
      blocked_on_real = classified.any? { |c| c["class"] == "valid_blocking" && c["finding"]["severity"].to_s.downcase == "blocking" }
      # More than one verdict can be right: a defect that lies in the requested
      # design itself may fairly be escalated instead of sent back.
      expected = Array(ref["expected_verdict"])
      # A blocking finding that is verified false sinks the review whatever
      # else it found: a real defect beside it does not excuse a false alarm.
      false_alarm = classified.any? { |c| c["class"] == "incorrect" && c["finding"]["severity"].to_s.downcase == "blocking" }
      basis = if false_alarm then "incorrect_blocking"
              elsif expected.include?(verdict) then "expected"
              elsif verdict == "CHANGES_REQUESTED" && blocked_on_real then "other_valid_blocking"
              else "unjustified"
              end
      rate = ->(n) { findings.empty? ? nil : (n.to_f / findings.size).round(3) }
      {
        "pass" => (critical - found).empty? && %w[expected other_valid_blocking].include?(basis), "format_ok" => true,
        "control" => defects.empty?,
        "critical_recall" => critical.empty? ? nil : ((critical & found).size.to_f / critical.size).round(3),
        "total_recall" => defects.empty? ? nil : (found.size.to_f / defects.size).round(3),
        "critical_missed" => critical - found, "defects_found" => found,
        "defect_severity" => credited.transform_values { |f| f["severity"].to_s.downcase },
        "findings" => findings.size,
        "finding_classes" => %w[defect duplicate valid_blocking incorrect process_note valid_out_of_scope unclassified].to_h { |k| [k, count.call(k)] },
        "incorrect_findings" => count.call("incorrect"), "duplicate_findings" => count.call("duplicate"),
        "valid_blocking" => count.call("valid_blocking"), "other_blocking_found" => classified.filter_map { |c| c["other_blocking"] }.uniq, "process_notes" => count.call("process_note"), "valid_out_of_scope" => count.call("valid_out_of_scope"),
        "unclassified_findings" => count.call("unclassified"), "adjudicated_findings" => classified.count { |c| c["adjudicated"] },
        # Kept for earlier readers: unmatched now means unclassified, and the
        # false-positive rate counts only findings verified incorrect.
        "unmatched_findings" => count.call("unclassified"),
        "false_positive_rate" => rate.call(count.call("incorrect")), "unclassified_rate" => rate.call(count.call("unclassified")),
        "blocking_non_defect" => blocking_other.map { |c| { "class" => c["class"], "line" => c["finding"]["line"], "summary" => c["finding"]["summary"] } },
        "spec_findings_cite_requirement" => spec_refs, "standards_findings_on_standards_axis" => standards_axis,
        "mechanical_duplicates" => classified.count { |c| c["mechanical"] },
        "acceptable_extras" => classified.filter_map { |c| c["acceptable"] },
        "verdict" => verdict, "expected_verdict" => expected.size == 1 ? expected.first : expected, "verdict_basis" => basis, "verdict_correct" => %w[expected other_valid_blocking].include?(basis),
        "detail" => classified.map { |c| c.merge("finding" => c["finding"].slice("axis", "severity", "path", "line", "requirement", "summary")) }
      }
    end

    def grade(task, final_text, workspace)
      send(task["grader"], task, final_text, workspace)
    end
  end
end

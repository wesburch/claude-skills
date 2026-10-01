# frozen_string_literal: true

# Aggregates run records. Evidence is grouped by the model and effort that
# actually ran (observed), never by what was requested; runs that are not
# valid model evidence are reported separately. Nothing here edits the model
# registry: output is LOCAL_EVAL evidence and a recommendation for a human.

require "json"

module Evals
  module Summary
    module_function

    def load_records(dir = Evals.results_dir, all_versions: false)
      # Run records only: results/<date>/<run>/record.json (artifacts may hold
      # delegate records of their own).
      Dir.glob(File.join(dir, "*", "*", "record.json")).sort.filter_map { |f| JSON.parse(File.read(f)) rescue nil }
        .select { |r| r["suite_version"] && r["run_id"] }
        .select { |r| all_versions || suite_versions.include?(r["suite_version"]) }
    end

    # The current suite version and the earlier ones declared comparable.
    def suite_versions
      [Evals.config["suite_version"], *Array(Evals.config["comparable_suite_versions"])]
    end

    def median(values)
      v = values.compact.sort
      return nil if v.empty?
      v.size.odd? ? v[v.size / 2] : ((v[v.size / 2 - 1] + v[v.size / 2]) / 2.0)
    end

    def key(rec)
      # Runs from comparable suite versions are one group: load_records has
      # already dropped every other version.
      [rec["task_id"], rec["host"], rec.dig("observed", "model") || "unobserved", rec.dig("observed", "effort") || "unobserved"]
    end

    def group(records)
      valid, invalid = records.partition { |r| r["valid_for_model_evidence"] }
      groups = valid.group_by { |r| key(r) }.map do |(task, host, model, effort), runs|
        passes = runs.count { |r| r["deterministic_pass"] }
        costs = runs.map { |r| r.dig("cost", "usd") }
        statuses = runs.map { |r| r.dig("cost", "status") }.uniq
        total_cost = costs.all? ? costs.sum : nil
        g = runs.map { |r| r["grader"] }
        {
          "task_id" => task, "host" => host, "model" => model, "effort" => effort, "suite_versions" => runs.map { |r| r["suite_version"] }.uniq.sort, "category" => runs.first["category"],
          "role" => runs.first["role"], "task_family" => runs.first["task_family"] || task,
          "experiment" => runs.first["experiment"], "variant" => runs.first["variant"],
          "valid_trials" => runs.size, "passes" => passes, "pass_rate" => (passes.to_f / runs.size).round(3),
          "median_wall_seconds" => median(runs.map { |r| r["wall_seconds"] }),
          "median_tokens" => { "input" => median(runs.map { |r| r.dig("tokens", "input") }),
                               "cached_input" => median(runs.map { |r| r.dig("tokens", "cached_input") }),
                               "output" => median(runs.map { |r| r.dig("tokens", "output") }) },
          "median_cost_usd" => median(costs), "cost_status" => statuses.join("+"),
          "cost_per_success_usd" => total_cost && passes.positive? ? (total_cost / passes).round(6) : nil,
          "median_repair_loops" => median(runs.map { |r| r.dig("repair_loops", "agent_failed_tool_results") }),
          "human_interventions" => runs.sum { |r| r["human_interventions"].to_i },
          "unrelated_change_runs" => runs.count { |r| !Array(r.dig("changes", "unrelated_paths")).empty? },
          "median_recall" => median(g.map { |x| x["recall"] || x["total_recall"] }),
          "median_precision" => median(g.map { |x| x["precision"] }),
          "critical_misses" => g.sum { |x| Array(x["critical_missed"]).size },
          "false_positive_rate" => median(g.map { |x| x["false_positive_rate"] }),
          "incorrect_findings" => g.sum { |x| x["incorrect_findings"].to_i },
          "unclassified_findings" => g.sum { |x| x["unclassified_findings"].to_i },
          "verdicts_correct" => g.first&.key?("verdict_correct") ? g.count { |x| x["verdict_correct"] } : nil,
          "behaviours" => g.first&.key?("behaviour") ? g.map { |x| x["behaviour"] }.tally : nil,
          "outcomes" => g.first&.key?("outcome") ? g.map { |x| x["outcome"] }.tally : nil,
          "median_packet_est_tokens" => median(runs.map { |r| r.dig("cost_breakdown", "preparation", "per_task_delegation", "packet", "est_tokens") }),
          "median_reply_est_tokens" => median(runs.map { |r| r.dig("cost_breakdown", "host_verification", "reply", "est_tokens") }),
          "mechanical_duplicates" => g.sum { |x| x["mechanical_duplicates"].to_i },
          "service_tier_served" => runs.map { |r| r.dig("service_tier", "served") }.uniq,
          # unknown accesses never invalidate, so a human has to see them here
          "isolation_unknown_runs" => runs.count { |r| %w[external_read external_write].any? { |k| r.dig("isolation_audit", k, "status") == "unknown" } },
          "cwd_escape_unpermitted_runs" => runs.count { |r| r.dig("isolation_audit", "cwd_escape", "permitted_by_task") == false },
          "run_ids" => runs.map { |r| r["run_id"] }
        }
      end
      excluded = invalid.map do |r|
        { "run_id" => r["run_id"], "task_id" => r["task_id"], "requested" => r["requested"], "observed" => r["observed"],
          "attributed_to" => r.dig("observed", "model") || "unobserved",
          "reasons" => invalid_reasons(r) }
      end
      [groups, excluded]
    end

    def invalid_reasons(r) = Evals.invalid_reasons(r)

    # Experiment tasks (`experiment` in task.yaml) measure something other
    # than a role's ordinary pass rate, so their runs never count as promotion
    # evidence on their own; importing any of them is an explicit later decision.
    def ordinary(groups) = groups.reject { |g| g["experiment"] }

    # LOCAL_EVAL evidence entries in the registry's local_eval schema. Written
    # to an artifact for review; never into registry/models.yaml.
    def local_eval_entries(groups)
      ordinary(groups).map do |g|
        { "tag" => "LOCAL_EVAL", "model" => g["model"], "category" => g["category"], "task_id" => g["task_id"], "host" => g["host"],
          "effort" => g["effort"], "date" => Time.now.utc.strftime("%Y-%m-%d"), "sample_size" => g["valid_trials"],
          "pass_rate" => g["pass_rate"], "median_cost_usd" => g["median_cost_usd"], "cost_per_success_usd" => g["cost_per_success_usd"],
          "cost_status" => g["cost_status"], "median_tokens" => g["median_tokens"], "median_repair_loops" => g["median_repair_loops"],
          "median_wall_seconds" => g["median_wall_seconds"], "human_interventions" => g["human_interventions"],
          "unrelated_edits" => g["unrelated_change_runs"],
          "seeded_defect" => g["category"] == "seeded-defect-review" ? { "recall" => g["median_recall"], "critical_misses" => g["critical_misses"] } : nil,
          "evidence_ref" => g["run_ids"] }
      end
    end

    # Evidence toward the promotion minimum, counted separately for each role,
    # host, model and effort (efforts are never pooled). Tasks sharing a
    # task_family count once. Below the minimum a result is preliminary.
    def promotion_readiness(groups)
      bar = Evals.config["promotion"]
      ordinary(groups).group_by { |g| g.values_at("role", "host", "model", "effort") }.map do |(role, host, model, effort), gs|
        samples = gs.sum { |g| g["valid_trials"] }
        families = gs.map { |g| g["task_family"] || g["task_id"] }.uniq.sort
        met = samples >= bar["min_valid_samples"] && families.size >= bar["min_distinct_tasks"]
        { "role" => role, "host" => host, "model" => model, "effort" => effort, "valid_samples" => samples,
          "distinct_tasks" => families.size, "tasks" => families,
          "status" => met ? "meets the sample minimum" : "preliminary",
          "needs" => "#{bar['min_valid_samples']} valid samples over #{bar['min_distinct_tasks']} distinct tasks" }
      end
    end

    # Recommendation only. Needs min_valid_trials on both sides and the
    # configured per-task bar; otherwise "insufficient evidence". A result that
    # clears the per-task bar stays preliminary until the candidate also meets
    # the promotion minimum for its model, effort and role.
    def recommend(groups, candidate:, reference:, task_id:)
      bar = Evals.config["acceptance"]
      c = groups.find { |g| g["task_id"] == task_id && "#{g['model']}@#{g['effort']}" == candidate }
      r = groups.find { |g| g["task_id"] == task_id && "#{g['model']}@#{g['effort']}" == reference }
      return "insufficient evidence: no valid runs for #{[c ? nil : candidate, r ? nil : reference].compact.join(' and ')}" unless c && r
      return "not applicable: #{task_id} belongs to experiment #{c['experiment'].inspect}, which is not promotion evidence" if c["experiment"]
      min = bar["min_valid_trials"]
      return "insufficient evidence: need #{min} valid trials each (have #{c['valid_trials']} and #{r['valid_trials']})" if [c, r].any? { |g| g["valid_trials"] < min }
      gate_loops = Array(Evals.config["repair_loop_gate_categories"]).include?(c["category"])
      ok = r["pass_rate"] - c["pass_rate"] <= bar["max_pass_rate_drop_vs_reference"] &&
           c["critical_misses"] <= bar["seeded_critical_misses_allowed"] &&
           (!gate_loops || c["median_repair_loops"].to_f <= bar["max_median_repair_loops"])
      cheaper = c["cost_per_success_usd"] && r["cost_per_success_usd"] && c["cost_per_success_usd"] < r["cost_per_success_usd"]
      ready = promotion_readiness(groups).find { |x| x.values_at("role", "host", "model", "effort") == c.values_at("role", "host", "model", "effort") }
      if !ok then "does not clear the bar"
      elsif ready["status"] == "preliminary"
        "preliminary: #{candidate} clears the per-task bar#{cheaper ? " at lower cost per success than #{reference}" : ''}, " \
          "with #{ready['valid_samples']} valid samples over #{ready['distinct_tasks']} distinct task(s); promotion needs #{ready['needs']}"
      elsif cheaper then "consider promotion (recommendation only): #{candidate} clears the bar at lower cost per success than #{reference}"
      else "clears the bar but is not cheaper per success than #{reference}"
      end
    end

    # Specification-sensitivity view of experiment tasks: one row per
    # experiment, variant, host, model and effort, pooled over task families
    # (each family is one base task), with the behaviour classes counted.
    def sensitivity(groups)
      groups.select { |g| g["experiment"] }.group_by { |g| g.values_at("experiment", "variant", "host", "model", "effort") }
            .map do |(experiment, variant, host, model, effort), gs|
        n = gs.sum { |g| g["valid_trials"] }
        passes = gs.sum { |g| g["passes"] }
        sum_tally = ->(k) { gs.map { |g| g[k] || {} }.reduce({}) { |a, b| a.merge(b) { |_, x, y| x + y } } }
        { "experiment" => experiment, "variant" => variant, "host" => host, "model" => model, "effort" => effort,
          "families" => gs.map { |g| g["task_family"] }.uniq.sort, "tasks" => gs.map { |g| g["task_id"] }.sort,
          "valid_trials" => n, "passes" => passes, "pass_rate" => n.positive? ? (passes.to_f / n).round(3) : nil,
          "behaviours" => sum_tally.call("behaviours"), "outcomes" => sum_tally.call("outcomes"),
          "unclassified" => sum_tally.call("outcomes")["unclassified"].to_i,
          "median_of_task_median_cost_usd" => median(gs.map { |g| g["median_cost_usd"] }) }
      end.sort_by { |x| x.values_at("experiment", "variant", "host", "model", "effort").map(&:to_s) }
    end
  end
end

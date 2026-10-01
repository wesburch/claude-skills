#!/usr/bin/env ruby
# frozen_string_literal: true

# evals/analysis/compare.rb MANIFEST.json
#
# Reproducible analysis of one comparison matrix. The manifest, the run
# directories it lists and its output are looked up in this checkout or in
# the attached evidence store (see evals/README.md). The manifest lists the
# approved configurations and the run directories that belong to the matrix
# (so proving runs and unrelated runs are never mixed in). Prints raw per-trial
# values and per-configuration aggregates; never edits the registry.
#
# Cost figures are API-equivalent estimates (tokens x list price), not
# subscription charges.

require "json"
require_relative "../lib/eval_support"

Encoding.default_external = Encoding::UTF_8
manifest = JSON.parse(File.read(ARGV[0] || abort("usage: compare.rb MANIFEST.json")))
records = manifest["run_dirs"].map { |d| JSON.parse(File.read(File.join(Evals.data_path(d), "record.json"))).merge("_dir" => d) }

def median(v)
  v = v.compact.sort
  return nil if v.empty?
  v.size.odd? ? v[v.size / 2] : (v[v.size / 2 - 1] + v[v.size / 2]) / 2.0
end

def stdev(v)
  v = v.compact
  return nil if v.size < 2
  m = v.sum.to_f / v.size
  Math.sqrt(v.sum { |x| (x - m)**2 } / (v.size - 1))
end

def r3(x) = x.is_a?(Float) ? x.round(3) : x

configs = manifest["configs"].map do |c|
  attempted = records.select { |r| [r["task_id"], r["host"], r.dig("requested", "model"), r.dig("requested", "effort")] == c.values_at("task", "host", "model", "effort") }
  # Evidence is attributed to the observed model: a valid run counts for this
  # configuration only if it observed the requested model and effort.
  valid = attempted.select { |r| r["valid_for_model_evidence"] && r["observed"] == r["requested"] }
  # Use the first N valid runs in time order (N = approved trials) so extra
  # replacement runs never cherry-pick a better trial.
  valid = valid.sort_by { |r| r["start"] }.first(manifest["trials"])
  g = valid.map { |r| r["grader"] }
  passes = valid.count { |r| r["deterministic_pass"] }
  cost_valid = valid.sum { |r| r.dig("cost", "usd").to_f }
  cost_all = attempted.sum { |r| r.dig("cost", "usd").to_f }
  per_trial = valid.map do |r|
    gr = r["grader"]
    {
      "run_id" => r["run_id"], "pass" => r["deterministic_pass"], "wall_s" => r["wall_seconds"]&.round(1),
      "cost_usd" => r.dig("cost", "usd")&.round(4), "tokens" => r["tokens"].slice("input", "cached_input", "output"),
      "repair_proxy" => r.dig("repair_loops", "agent_failed_tool_results"),
      "recall" => gr["recall"], "precision" => gr["precision"], "false_positives" => gr["false_positives"],
      "acceptable_extras" => gr["acceptable_extras"],
      "tests" => gr["tests_total"] && "#{gr['tests_passed']}/#{gr['tests_total']}", "unrelated" => gr["unrelated_paths"],
      "critical_missed" => gr["critical_missed"], "defects_found" => gr["defects_found"], "findings" => gr["findings"],
      "unmatched" => gr["unmatched_findings"], "mechanical_duplicates" => gr["mechanical_duplicates"],
      "finding_classes" => gr["finding_classes"], "defect_severity" => gr["defect_severity"],
      "blocking_non_defect" => gr["blocking_non_defect"]&.size,
      "verdict" => gr["verdict"], "verdict_correct" => gr["verdict_correct"],
      "variant" => gr["variant"], "behaviour" => gr["behaviour"], "outcome" => gr["outcome"], "unclassified_reason" => gr["unclassified_reason"]
    }.compact
  end
  excluded = (attempted - valid).map do |r|
    reasons = Evals.invalid_reasons(r)
    reasons = ["valid but beyond the approved #{manifest['trials']} trials (not used)"] if reasons.empty?
    { "run_id" => r["run_id"], "observed" => r["observed"], "reasons" => reasons, "pass" => r["deterministic_pass"], "cost_usd" => r.dig("cost", "usd")&.round(4) }
  end
  walls = valid.map { |r| r["wall_seconds"] }
  costs = valid.map { |r| r.dig("cost", "usd") }
  {
    "config" => c, "attempted" => attempted.size, "valid" => valid.size, "passes" => passes,
    "pass_rate" => valid.empty? ? nil : r3(passes.to_f / valid.size),
    "median_recall" => median(g.map { |x| x["recall"] || x["total_recall"] }),
    "median_precision" => median(g.map { |x| x["precision"] }),
    "critical_recall" => g.first&.key?("critical_recall") ? median(g.map { |x| x["critical_recall"] }) : nil,
    "critical_misses_total" => g.first&.key?("critical_missed") ? g.sum { |x| x["critical_missed"].size } : nil,
    "critical_missed_by_trial" => g.first&.key?("critical_missed") ? g.map { |x| x["critical_missed"] } : nil,
    # Explore false positives plus review findings verified incorrect. Review
    # findings still unclassified are reported apart; they are not errors.
    "false_positive_count" => g.sum { |x| Array(x["false_positives"]).size + (x["incorrect_findings"] || x["unmatched_findings"]).to_i },
    "unclassified_findings" => g.sum { |x| x["unclassified_findings"].to_i },
    "finding_classes" => g.first&.key?("finding_classes") ? g.map { |x| x["finding_classes"] }.reduce { |a, b| a.merge(b) { |_, p, q| p + q } } : nil,
    "defect_severity_by_trial" => g.first&.key?("defect_severity") ? g.map { |x| x["defect_severity"] } : nil,
    "verdicts" => g.first&.key?("verdict") ? g.map { |x| x["verdict"] } : nil,
    # impl_spec: one behaviour class and outcome per trial (pass, noncompliant, fail, unclassified).
    "behaviours" => g.first&.key?("behaviour") ? g.map { |x| x["behaviour"] }.tally : nil,
    "outcomes" => g.first&.key?("outcome") ? g.map { |x| x["outcome"] }.tally : nil,
    "blocking_non_defect" => g.first&.key?("blocking_non_defect") ? g.sum { |x| x["blocking_non_defect"].size } : nil,
    "median_delegate_wall_s" => median(valid.map { |r| r.dig("cost_breakdown", "delegate_execution", "wall_seconds") })&.round(1),
    "packet_est_tokens" => valid.map { |r| r.dig("cost_breakdown", "preparation", "per_task_delegation", "packet", "est_tokens") }.uniq,
    "median_reply_est_tokens" => median(valid.map { |r| r.dig("cost_breakdown", "host_verification", "reply", "est_tokens") }),
    "median_false_positive_rate" => median(g.map { |x| x["false_positive_rate"] }),
    "verdict_correct" => g.first&.key?("verdict_correct") ? "#{g.count { |x| x['verdict_correct'] }}/#{g.size}" : nil,
    "mechanical_duplicates" => g.sum { |x| x["mechanical_duplicates"].to_i },
    "tests" => g.first&.key?("tests_total") ? g.map { |x| "#{x['tests_passed']}/#{x['tests_total']}" } : nil,
    "unrelated_edit_runs" => valid.count { |r| !Array(r.dig("changes", "unrelated_paths")).empty? },
    "repair_proxy" => valid.map { |r| r.dig("repair_loops", "agent_failed_tool_results") },
    "median_repair_proxy" => median(valid.map { |r| r.dig("repair_loops", "agent_failed_tool_results") }),
    "harness_repair_loops" => valid.sum { |r| r.dig("repair_loops", "harness").to_i },
    "human_interventions" => valid.sum { |r| r["human_interventions"].to_i },
    "median_wall_s" => median(walls)&.round(1), "wall_range_s" => walls.empty? ? nil : [walls.min.round(1), walls.max.round(1)],
    "wall_stdev_s" => stdev(walls)&.round(1),
    "median_tokens" => %w[input cached_input output].to_h { |k| [k, median(valid.map { |r| r.dig("tokens", k) })] },
    "median_cost_usd" => median(costs)&.round(4), "cost_range_usd" => costs.empty? ? nil : [costs.min.round(4), costs.max.round(4)],
    "total_cost_valid_usd" => cost_valid.round(4), "total_cost_attempted_usd" => cost_all.round(4),
    "cost_per_success_usd" => passes.positive? ? (cost_valid / passes).round(4) : nil,
    "cost_per_success_incl_excluded_usd" => passes.positive? ? (cost_all / passes).round(4) : nil,
    "service_tier" => valid.map { |r| r["service_tier"] }.uniq,
    "isolation" => {
      "unknown_read_runs" => valid.count { |r| r.dig("isolation_audit", "external_read", "status") == "unknown" },
      "unknown_write_runs" => valid.count { |r| r.dig("isolation_audit", "external_write", "status") == "unknown" },
      "cwd_escape_runs" => valid.count { |r| r.dig("isolation_audit", "cwd_escape", "occurred") },
      "cwd_escape_unpermitted_runs" => valid.count { |r| r.dig("isolation_audit", "cwd_escape", "permitted_by_task") == false },
      "prevented_events" => valid.sum { |r| %w[external_read external_write].sum { |k| Array(r.dig("isolation_audit", k, "events")).count { |e| e["status"] == "prevented" } } }
    },
    "trials" => per_trial, "excluded" => excluded
  }
end

out = {
  "matrix" => manifest["name"], "suite_version" => records.map { |r| r["suite_version"] }.uniq,
  # What the model saw (packet, role, guard, delegate) must be identical
  # within each task/host; audit and grader code may differ after a regrade.
  "runtime_consistent" => records.group_by { |r| [r["task_id"], r["host"]] }.all? do |_, rs|
    rs.map { |r| r.dig("harness", "digests")&.slice("packet", "role", "guard", "codex-delegate") }.uniq.size == 1
  end,
  "grading_versions" => records.map { |r| r["grading_version"] || "grade-v1" }.uniq,
  "grader_fingerprints" => records.map { |r| r["grader_fingerprint"] }.uniq.size,
  "runs_attempted" => records.size, "total_cost_attempted_usd" => records.sum { |r| r.dig("cost", "usd").to_f }.round(4),
  "cost_note" => "API-equivalent estimates (list price x tokens); not subscription charges",
  "configs" => configs
}
File.write(Evals.data_path(manifest["output"]), JSON.pretty_generate(out)) if manifest["output"]

puts "#{out['matrix']}: #{out['runs_attempted']} runs attempted, $#{out['total_cost_attempted_usd']} API-equivalent; " \
     "runtime consistent per task/host: #{out['runtime_consistent']}; grading #{out['grading_versions'].join(',')}; grader fingerprints #{out['grader_fingerprints']}"
puts format("%-24s %-6s %-18s %-6s %7s %5s %6s %6s %6s %7s %8s %9s %9s %s", "task", "host", "model", "effort", "valid/n", "pass", "recall", "prec", "cmiss", "wall", "med$", "$/ok", "$/ok+ex", "fp/dup/rep")
configs.each do |c|
  k = c["config"]
  puts format("%-24s %-6s %-18s %-6s %7s %5s %6s %6s %6s %7s %8s %9s %9s %s", k["task"][0, 24], k["host"].sub("claude-code", "claude"), k["model"], k["effort"],
              "#{c['valid']}/#{c['attempted']}", c["pass_rate"].inspect, c["median_recall"].inspect, c["median_precision"].inspect,
              c["critical_misses_total"].inspect, c["median_wall_s"].inspect, c["median_cost_usd"].inspect, c["cost_per_success_usd"].inspect,
              c["cost_per_success_incl_excluded_usd"].inspect, "#{c['false_positive_count']}/#{c['mechanical_duplicates']}/#{c['repair_proxy'].inspect}" +
              (c.dig("isolation", "unknown_read_runs").to_i + c.dig("isolation", "unknown_write_runs").to_i).then { |u| u.positive? ? " ISOLATION-UNKNOWN=#{u}" : "" } +
              (c["behaviours"] ? " #{c['behaviours'].map { |b, n| "#{b}=#{n}" }.join(' ')}" : ""))
end

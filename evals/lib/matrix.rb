# frozen_string_literal: true

# Turns a matrix spec (which role, host, effort tier and selection to compare)
# into a manifest of concrete task/host/model/effort configurations, resolved
# from the model registry by engineering-workflow's resolver rather than typed
# by hand. The manifest records the registry revision it was resolved
# against. Nothing here runs a model or edits the registry.
#
# Spec (YAML):
#   name: <matrix name>
#   trials: 3
#   output: analysis/<results file>.json   # optional; read by analysis/compare.rb
#   tasks: [<task id>, ...]
#   configs:
#     - { role: wf-implementer, host: claude-code, tier: standard, select: incumbent }
#     - { role: wf-implementer, host: claude-code, tier: standard, select: candidates }
#
# Experiment tasks (`experiment` in task.yaml) are recorded in `tasks_meta`
# with their experiment, experiment_version (absent means 1), variant and
# family, so analysis/compare.rb and `bin/summarize --manifest` can refuse a
# listed run from another experiment or version.
#
# `incumbent` is what the resolver selects for the role, host and tier.
# `candidates` is every candidate the resolver lists as awaiting evidence,
# each resolved as an explicit choice at the same tier; one the account cannot
# use is skipped with the resolver's reason, never substituted.

require "digest"
require "json"
require "open3"
require "time"
require "yaml"
require_relative "eval_support"

module Evals
  module Matrix
    module_function

    SELECTIONS = %w[incumbent candidates].freeze
    REGISTRY = File.join("engineering-workflow", "registry", "models.yaml")

    # The real resolver: `model-routing resolve ... --json`.
    def model_routing(role:, host:, tier:, user_model: nil)
      argv = [File.join(Evals::SCRIPTS, "model-routing"), "resolve", "--role", role, "--host", host, "--tier", tier, "--json"]
      argv += ["--user-model", user_model] if user_model
      out, err, st = Open3.capture3(*argv)
      JSON.parse(out)
    rescue JSON::ParserError
      { "status" => "resolver_error", "notes" => ["exit #{st&.exitstatus}: #{err.to_s.strip[0, 200]}"] }
    end

    def harness_available(host, model)
      Evals.model_available!(host, model)
      nil
    rescue Evals::Error => e
      e.message
    end

    def registry_revision
      path = File.join(Evals::REPO, REGISTRY)
      commit, = Open3.capture2("git", "-C", Evals::REPO, "log", "-1", "--format=%H", "--", REGISTRY)
      dirty, = Open3.capture2("git", "-C", Evals::REPO, "status", "--porcelain", "--", REGISTRY)
      { "path" => REGISTRY, "sha256" => Digest::SHA256.file(path).hexdigest, "last_commit" => commit.strip, "uncommitted_changes" => !dirty.strip.empty? }
    end

    # Problems with the spec itself; empty when it can be resolved.
    def spec_problems(spec)
      return ["spec is not a mapping"] unless spec.is_a?(Hash)
      p = []
      p << "name is required" if spec["name"].to_s.strip.empty?
      p << "trials must be a positive integer" unless spec["trials"].is_a?(Integer) && spec["trials"].positive?
      p << "tasks must be a non-empty list" unless spec["tasks"].is_a?(Array) && !spec["tasks"].empty?
      p << "configs must be a non-empty list" unless spec["configs"].is_a?(Array) && !spec["configs"].empty?
      Array(spec["configs"]).each_with_index do |c, i|
        next p << "config #{i}: not a mapping" unless c.is_a?(Hash)
        missing = %w[role host tier select].select { |k| c[k].to_s.strip.empty? }
        p << "config #{i}: #{missing.join(', ')} required" unless missing.empty?
        p << "config #{i}: select must be one of #{SELECTIONS.join('/')}" unless missing.include?("select") || SELECTIONS.include?(c["select"])
      end
      p
    end

    # resolver: (role:, host:, tier:, user_model:) -> resolver JSON hash
    # available: (host, model) -> nil when the harness can run it, else why not
    # tasks: task id -> Evals::Task (or anything answering ["role"] and the
    #        experiment fields)
    def resolve(spec, resolver: method(:model_routing), available: method(:harness_available),
                tasks: ->(id) { Evals.load_task(id) }, registry: nil)
      problems = spec_problems(spec)
      raise Evals::Error, "matrix spec: #{problems.join('; ')}" unless problems.empty?
      allowed = Array(Evals.config["allowed_efforts"])
      resolutions = []
      skipped = []
      chosen = []
      spec["configs"].each do |c|
        base = resolver.call(role: c["role"], host: c["host"], tier: c["tier"], user_model: nil)
        picks =
          if c["select"] == "incumbent"
            [[base, nil]]
          else
            Array(base["candidates_awaiting_evidence"]).map { |m| [resolver.call(role: c["role"], host: c["host"], tier: c["tier"], user_model: m), m] }
          end
        skipped << { "config" => c, "reason" => "the resolver lists no candidate awaiting evidence" } if picks.empty?
        picks.each do |res, wanted|
          entry = c.merge("status" => res["status"], "model" => res["model"], "effort" => res["effort"],
                          "model_status" => res["model_status"], "notes" => Array(res["notes"])).compact
          resolutions << entry
          why =
            if res["status"] != "ok" then "resolver status #{res['status'].inspect}: #{Array(res['notes']).last}"
            elsif wanted && res["model"] != wanted then "resolver returned #{res['model']} for candidate #{wanted}"
            elsif !allowed.include?(res["effort"]) then "effort #{res['effort'].inspect} is outside allowed_efforts"
            else available.call(c["host"], res["model"])
            end
          next skipped << { "config" => c, "model" => wanted || res["model"], "reason" => why } if why
          chosen << c.slice("role", "host", "tier", "select").merge("model" => res["model"], "effort" => res["effort"])
        end
      end
      configs = spec["tasks"].flat_map do |id|
        role = tasks.call(id)["role"]
        chosen.select { |c| c["role"] == role }.map { |c| { "task" => id, "host" => c["host"], "model" => c["model"], "effort" => c["effort"] }.merge(c.slice("role", "tier", "select")) }
      end
      raise Evals::Error, "no configuration resolved for any task" if configs.empty?
      meta = spec["tasks"].to_h { |id| [id, tasks.call(id)] }.select { |_, t| t["experiment"] }.transform_values do |t|
        { "experiment" => t["experiment"], "experiment_version" => t["experiment_version"] || 1, "variant" => t["variant"], "task_family" => t["task_family"] }.compact
      end
      {
        "name" => spec["name"], "trials" => spec["trials"], "output" => spec["output"],
        "resolved_at" => Time.now.utc.iso8601, "registry" => registry || registry_revision,
        "spec" => spec.slice("tasks", "configs"), "resolutions" => resolutions, "skipped" => skipped,
        "configs" => configs, "tasks_meta" => meta.empty? ? nil : meta, "run_dirs" => []
      }.compact
    end
  end
end

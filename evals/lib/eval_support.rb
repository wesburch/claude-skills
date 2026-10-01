# frozen_string_literal: true

# Eval support: task loading, workspace export, isolated launchers for
# Claude Code and Codex, observation and run records. Tasks, hidden data and
# results may live in this checkout or in an optional private evidence store. The isolation audit
# (contamination) lives in isolation_audit.rb.
# Graders live in graders.rb; hidden reference data lives in evals/hidden and
# is read only by graders, never placed in a model-visible packet.

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require "digest"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require "shellwords"
require "time"
require "tmpdir"
require "yaml"
require_relative "isolation_audit"

module Evals
  ROOT = File.expand_path("..", __dir__)
  REPO = File.expand_path("..", ROOT)
  SCRIPTS = File.join(REPO, "engineering-workflow", "scripts")
  HIDDEN = File.join(ROOT, "hidden")
  require File.join(SCRIPTS, "lib", "routing_support")

  class Error < StandardError; end

  module_function

  # ---------------------------------------------------------------- evidence store

  # An optional private directory holding tasks/, hidden/, results/,
  # analysis/ and a config.local.yaml. It is named by EVAL_STORE, or by
  # `store:` in evals/config.local.yaml (gitignored). EVAL_STORE=none forces
  # public-only mode. nil when none is attached; nothing here requires one.
  def store
    return @store if defined?(@store)
    path = ENV["EVAL_STORE"].to_s
    local = File.join(ROOT, "config.local.yaml")
    path = (YAML.safe_load(File.read(local)) || {})["store"].to_s if path.empty? && File.file?(local)
    path = "" if path == "none"
    full = path.empty? ? nil : File.expand_path(path)
    @store = full && File.directory?(full) ? full : nil
  end

  # Where tasks and data may be found: this checkout first, then the store.
  def data_roots = [ROOT, store].compact

  # A path such as "tasks/x/packet.md", "results/2026-01-01/run" or
  # "lib/graders.rb" (an older "evals/" prefix is accepted): wherever it
  # exists, preferring the store; new files go to the store when attached.
  def data_path(rel, roots: data_roots)
    rel = rel.to_s.delete_prefix("evals/")
    roots.reverse.map { |root| File.join(root, rel) }.find { |p| File.exist?(p) } || File.join(roots.last, rel)
  end

  # The committed configuration, with the store's config.local.yaml (source
  # repository paths and other machine-specific values) merged over it.
  def config
    @config ||= begin
      base = YAML.safe_load(File.read(File.join(ROOT, "config.yaml")))
      extra = store && File.file?(File.join(store, "config.local.yaml")) ? YAML.safe_load(File.read(File.join(store, "config.local.yaml"))) || {} : {}
      base.merge(extra) { |_, a, b| a.is_a?(Hash) && b.is_a?(Hash) ? a.merge(b) : b }
    end
  end
  def registry = (@registry ||= YAML.safe_load(File.read(File.join(REPO, "engineering-workflow", "registry", "models.yaml")), permitted_classes: [Date]))

  def repo_path(name)
    env = ENV["EVAL_REPO_#{name.upcase.tr('-', '_')}"]
    path = env && !env.empty? ? env : Hash(config["repos"])[name]
    raise Error, "source repository #{name.inspect} is not configured (set EVAL_REPO_#{name.upcase.tr('-', '_')} or add it to the store's config.local.yaml)" unless path
    File.expand_path(path)
  end

  # ---------------------------------------------------------------- tasks

  Task = Struct.new(:id, :dir, :data) do
    def [](k) = data[k]
    def packet_path = File.join(dir, data.fetch("packet"))
    def packet_text = File.read(packet_path)
    # Hidden data sits beside the tasks directory the task came from.
    def hidden_dir = File.join(File.dirname(File.dirname(dir)), "hidden", id)
    def fixture? = !data["fixture"].nil?
    def read_only? = data["access"] == "read-only"
    def owned = Array(data["owned_files"])
    def scope = Array(data["scope"])
  end

  def task_dirs = data_roots.map { |root| File.join(root, "tasks") }.select { |d| File.directory?(d) }
  def task_ids = task_dirs.flat_map { |t| Dir.children(t).select { |d| File.exist?(File.join(t, d, "task.yaml")) } }.uniq.sort
  def hidden_roots = data_roots.map { |root| File.join(root, "hidden") }.select { |d| File.directory?(d) }

  def load_task(id)
    dir = task_dirs.map { |t| File.join(t, id) }.find { |d| File.exist?(File.join(d, "task.yaml")) }
    raise Error, "unknown task #{id}#{store ? '' : ' (no private evidence store is attached)'}" unless dir
    Task.new(id, dir, YAML.safe_load(File.read(File.join(dir, "task.yaml"))))
  end

  # ---------------------------------------------------------------- frozen tasks

  # A task that declares `task_version` is frozen: it may not run or be
  # regraded unless analysis/<freeze name>-freeze-v<task_version>.json
  # exists and every input it lists still has its recorded hash. The freeze
  # name is `freeze_name`, else the task family, else the task id, so a
  # family can hold tasks frozen separately (a historical task and later
  # variants of it). Returns what is wrong; empty when the task is not
  # frozen or everything matches.
  def freeze_file(task) = "analysis/#{task['freeze_name'] || task['task_family'] || task.id}-freeze-v#{task['task_version']}.json"

  def frozen_mismatches(task, root: nil)
    roots = root ? [root] : data_roots
    return [] unless task["task_version"]
    file = data_path(freeze_file(task), roots: roots)
    return ["#{File.basename(file)} is missing"] unless File.file?(file)
    Hash(JSON.parse(File.read(file))["sha256"]).filter_map do |rel, want|
      full = data_path(rel, roots: roots)
      rel unless File.file?(full) && Digest::SHA256.file(full).hexdigest == want
    end
  end

  # ---------------------------------------------------------------- workspace

  def git(dir, *args, env: {})
    out, err, st = Open3.capture3(env, "git", "-C", dir, *args)
    raise Error, "git #{args.first(2).join(' ')} failed in #{dir}: #{err.strip}" unless st.success?
    out
  end

  # Fresh export of the task's tree at its SHA with no history (future commits
  # stay unreachable), committed once so the model sees a normal clean repo.
  def prepare_workspace(task, parent_dir)
    ws = File.join(parent_dir, "workspace")
    FileUtils.mkdir_p(ws)
    scope = task.scope == ["."] ? [] : task.scope
    if task.fixture?
      # A self-contained task: its base tree is a directory inside the task.
      FileUtils.cp_r(File.join(task.dir, task["fixture"], "."), ws, preserve: true)
    else
      src = repo_path(task["repo"])
      raise Error, "source repo missing: #{src}" unless File.directory?(File.join(src, ".git"))
      cmd = "git -C #{Shellwords.escape(src)} archive --format=tar #{Shellwords.escape(task['sha'])} " \
            "#{scope.map { |s| Shellwords.escape(s) }.join(' ')} | tar -x -C #{Shellwords.escape(ws)}"
      _, err, st = Open3.capture3("bash", "-o", "pipefail", "-c", cmd)
      raise Error, "export failed: #{err.strip}" unless st.success?
    end
    # Neutral identity and message: nothing in `git log` may hint at the task.
    id_env = { "GIT_AUTHOR_NAME" => "developer", "GIT_AUTHOR_EMAIL" => "developer@example.invalid",
               "GIT_COMMITTER_NAME" => "developer", "GIT_COMMITTER_EMAIL" => "developer@example.invalid",
               "GIT_AUTHOR_DATE" => "2000-01-01T00:00:00Z", "GIT_COMMITTER_DATE" => "2000-01-01T00:00:00Z" }
    git(ws, "init", "-q")
    git(ws, "add", "-A")
    git(ws, "commit", "-q", "--no-verify", "-m", "base", env: id_env)
    tree = git(ws, "rev-parse", "HEAD^{tree}").strip
    if task["overlay"]
      overlay = File.join(task.dir, task["overlay"])
      Dir.glob("**/*", base: overlay).each do |rel|
        next if File.directory?(File.join(overlay, rel))
        FileUtils.mkdir_p(File.dirname(File.join(ws, rel)))
        FileUtils.cp(File.join(overlay, rel), File.join(ws, rel), preserve: true)
        git(ws, "add", "-N", rel)
      end
    end
    apply_overlay_sha(task, src, ws, scope) if task["overlay_sha"]
    [ws, tree]
  end

  # A change under review taken from history: the same scope exported at a
  # later commit, laid over the base as an uncommitted working-tree change.
  # Only files are copied (no history), files the later commit removed are
  # removed, and the result must equal the task's pinned `overlay_tree`.
  def apply_overlay_sha(task, src, ws, scope)
    sha = task["overlay_sha"]
    removed = git(src, "diff", "--no-renames", "--name-only", "-z", "--diff-filter=D", task["sha"], sha, "--", *scope).split("\0")
    removed.each { |rel| FileUtils.rm_f(File.join(ws, rel)) }
    cmd = "git -C #{Shellwords.escape(src)} archive --format=tar #{Shellwords.escape(sha)} " \
          "#{scope.map { |s| Shellwords.escape(s) }.join(' ')} | tar -x -C #{Shellwords.escape(ws)}"
    _, err, st = Open3.capture3("bash", "-o", "pipefail", "-c", cmd)
    raise Error, "overlay export failed: #{err.strip}" unless st.success?
    Dir.mktmpdir("eval-index-") do |tmp|
      env = { "GIT_INDEX_FILE" => File.join(tmp, "index") }
      git(ws, "add", "-A", env: env)
      got = git(ws, "write-tree", env: env).strip
      raise Error, "overlay tree #{got} does not match the pinned overlay_tree #{task['overlay_tree'].inspect}" unless got == task["overlay_tree"]
    end
    git(ws, "add", "-A", "-N")
  end

  def file_digests(root)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: root).each_with_object({}) do |rel, h|
      next if rel == ".git" || rel.start_with?(".git/") || %w[. ..].include?(File.basename(rel))
      full = File.join(root, rel)
      h[rel] = Digest::SHA256.file(full).hexdigest if File.file?(full) && !File.symlink?(full)
    end
  end

  def changed_paths(before, after)
    (before.keys | after.keys).reject { |k| before[k] == after[k] }.sort
  end

  def source_state(task)
    if task.fixture?
      files = Dir.glob(File.join(task.dir, task["fixture"], "**", "*"), File::FNM_DOTMATCH).select { |f| File.file?(f) }.sort
      return { "head" => "fixture", "status_digest" => Digest::SHA256.hexdigest(files.map { |f| Digest::SHA256.file(f).hexdigest }.join) }
    end
    src = repo_path(task["repo"])
    head = git(src, "rev-parse", "HEAD").strip
    # The harness writes each run's own record under evals/results while the
    # run is in flight; when this repo is also the task's source, that must
    # not read as a change to the source.
    status = git(src, "status", "--porcelain", "--", ".", ":!evals/results")
    { "head" => head, "status_digest" => Digest::SHA256.hexdigest(status) }
  end

  # ---------------------------------------------------------------- roles

  def claude_role(role)
    text = File.read(File.join(REPO, "agents", "claude", "#{role}.md"))
    m = text.match(/\A---\s*\n(.*?)\n---\s*\n(.*)\z/m) or raise Error, "bad role file #{role}"
    [YAML.safe_load(m[1]), m[2].strip]
  end

  def guard_path = File.join(SCRIPTS, "readonly-bash-guard")

  # Bash runs in Claude Code's OS sandbox: no network, writes only to the
  # workspace and per-user temp, no reads under the home directory (source
  # repos and hidden data live there), no unsandboxed retry, and refusal to
  # start if the sandbox is unavailable. File tools are denied under home too.
  EVAL_SANDBOX_SETTINGS = {
    "sandbox" => { "enabled" => true, "failIfUnavailable" => true, "allowUnsandboxedCommands" => false,
                   "filesystem" => { "denyRead" => ["~"] } },
    "permissions" => { "deny" => %w[Read(~/**) Edit(~/**) Write(~/**) Glob(~/**) Grep(~/**)] }
  }.freeze

  # Git ignores the user's global and system config inside eval runs.
  EVAL_ENV = { "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_NOSYSTEM" => "1" }.freeze

  # Local tools only: no MCP servers (strict, empty config), no user/project
  # settings (--restricted), file tools confined to the workspace, sandboxed
  # Bash; read-only roles also get the Bash guard confined to the workspace.
  def claude_command(task, model:, effort:, artifacts:, role_body:, workspace: nil)
    mcp = File.join(artifacts, "mcp-empty.json")
    File.write(mcp, JSON.generate({ "mcpServers" => {} }))
    tools = task.read_only? ? %w[Read Grep Glob Bash] : %w[Read Grep Glob Bash Edit Write]
    argv = ["claude", "-p", "--restricted", "--tools", tools.join(","), "--strict-mcp-config", "--mcp-config", mcp,
            "--model", model, "--effort", effort, "--append-system-prompt", role_body,
            "--output-format", "stream-json", "--verbose",
            "--allowedTools", *(task.read_only? ? %w[Bash] : %w[Bash Edit Write])]
    settings = JSON.parse(JSON.generate(EVAL_SANDBOX_SETTINGS))
    if task.read_only?
      settings["hooks"] = { "PreToolUse" => [{ "matcher" => "Bash", "hooks" =>
        [{ "type" => "command", "command" => "#{Shellwords.escape(guard_path)} || exit 2" }] }] }
    end
    argv += ["--settings", JSON.generate(settings)]
    env = EVAL_ENV.dup
    env["READONLY_GUARD_ROOT"] = workspace if task.read_only? && workspace
    { "argv" => argv, "env" => env, "settings" => settings, "tools" => tools, "mcp_servers" => [],
      "settings_sources" => "none (--restricted) plus --settings",
      "bash_guard" => task.read_only? ? "readonly-bash-guard, READONLY_GUARD_ROOT=workspace" : "none (write role; sandboxed)" }
  end

  def codex_command(task, model:, effort:, ws:, packet_file:, out:, timeout: 1800)
    argv = [File.join(SCRIPTS, "codex-delegate"), "--role", task["role"], "--cwd", ws, "--model", model,
            "--effort", effort, "--packet", packet_file, "--out", out, "--eval", "--timeout", timeout.to_s]
    { "argv" => argv, "profile" => "codex-delegate --eval: ignore user config and rules, hooks/agents/multi-agent/" \
                                   "web search/image generation/goals disabled, standard tier, role sandbox" }
  end

  # ---------------------------------------------------------------- availability

  def claude_cli_version = Open3.capture2("claude", "--version").first[/\d+\.\d+\.\d+/]

  def model_available!(host, model)
    m = registry["models"].find { |x| x["id"] == model }
    raise Error, "#{model} is not in the registry" unless m
    raise Error, "#{model} is not a #{host} model" unless Array(m["hosts"]).include?(host)
    case host
    when "codex"
      cache = JSON.parse(File.read(File.join(Dir.home, ".codex", "models_cache.json"))) rescue {}
      accessible = Array(cache["models"]).select { |x| x["visibility"] == "list" }.map { |x| x["slug"] }
      raise Error, "#{model} is Listed but not Accessible to this account; not probing it" unless accessible.include?(model)
    when "claude-code"
      req = m.dig("min_cli", "claude-code")
      v = claude_cli_version
      if req && !(v && (v.split(".").map(&:to_i) <=> req.to_s.split(".").map(&:to_i)) >= 0)
        raise Error, "#{model} needs Claude Code #{req}; installed #{v}"
      end
    end
    m
  end

  # ---------------------------------------------------------------- observation

  def parse_stream(path)
    File.foreach(path).filter_map { |l| JSON.parse(l) rescue nil }
  end

  def claude_observation(events)
    init = events.find { |e| e["type"] == "system" && e["subtype"] == "init" } || {}
    result = events.find { |e| e["type"] == "result" } || {}
    session = init["session_id"] || result["session_id"]
    transcript = session && Dir.glob(File.join(Dir.home, ".claude", "projects", "*", "#{session}.jsonl")).first
    efforts = []
    if transcript
      File.foreach(transcript) do |l|
        e = (JSON.parse(l) rescue nil)
        efforts << e["effort"] if e.is_a?(Hash) && e["type"] == "assistant" && e["effort"].is_a?(String)
      end
    end
    efforts.uniq!
    models = (result["modelUsage"] || {}).keys
    models = [init["model"]].compact if models.empty?
    usage = result["usage"] || {}
    {
      "model" => models.size == 1 ? models.first : (models.empty? ? nil : models.sort.join("+")),
      "effort" => efforts.size == 1 ? efforts.first : (efforts.empty? ? nil : efforts.join("+")),
      "tools" => init["tools"], "mcp_servers" => init["mcp_servers"], "permission_mode" => init["permissionMode"],
      "session_id" => session, "transcript" => transcript,
      "tokens" => { "input" => usage["input_tokens"].to_i + usage["cache_creation_input_tokens"].to_i,
                    "cached_input" => usage["cache_read_input_tokens"].to_i, "output" => usage["output_tokens"].to_i },
      "tier_telemetry" => usage.slice("service_tier", "speed", "fallback_credit").merge(result.select { |k, _| k.to_s.include?("fallback") }),
      "cost_usd" => result["total_cost_usd"], "is_error" => result["is_error"], "final_text" => result["result"].to_s,
      "duration_ms" => result["duration_ms"]
    }
  end

  def environment_fingerprint
    digest = ->(p) { File.exist?(p) ? Digest::SHA256.file(p).hexdigest[0, 16] : nil }
    { "claude_cli" => (Open3.capture2("claude", "--version").first[/\d+\.\d+\.\d+/] rescue nil),
      "codex_cli" => (Open3.capture2("codex", "--version").first[/\d+\.\d+\.\d+/] rescue nil),
      "global_instructions" => { "~/.claude/CLAUDE.md" => digest.call(File.join(Dir.home, ".claude", "CLAUDE.md")),
                                 "~/.codex/AGENTS.md" => digest.call(File.join(Dir.home, ".codex", "AGENTS.md")) },
      "registry_last_reviewed" => registry["last_reviewed"].to_s }
  end

  def failed_tool_results_claude(events)
    events.select { |e| e["type"] == "user" }.sum do |e|
      Array(e.dig("message", "content")).count do |c|
        next false unless c.is_a?(Hash) && c["type"] == "tool_result" && c["is_error"] == true
        text = c["content"].is_a?(Array) ? c["content"].map { |x| x["text"].to_s }.join : c["content"].to_s
        text !~ /Read-only role \(|denied by your permission settings|PreToolUse/ # harness denials are not repair loops
      end
    end
  end

  def failed_tool_results_codex(rollout)
    return 0 unless rollout && File.exist?(rollout)
    File.foreach(rollout).count do |l|
      l.include?("function_call_output") && l =~ /(Exit code|exit_code)\W+([1-9]\d*)/
    end
  end

  # Runs a command with stdin, killing its process group on timeout.
  def run_timed(env, argv, stdin_data:, chdir: Dir.pwd, timeout: 1800)
    out = +""
    err = +""
    status = nil
    Open3.popen3(env, *argv, chdir: chdir, pgroup: true) do |i, o, e, t|
      readers = [Thread.new { out << o.read.to_s }, Thread.new { err << e.read.to_s }]
      begin
        i.write(stdin_data)
      rescue Errno::EPIPE
        nil
      end
      i.close
      unless t.join(timeout)
        Process.kill("TERM", -t.pid) rescue nil
        sleep 2
        Process.kill("KILL", -t.pid) rescue nil
        err << "\n[evals] killed after #{timeout}s timeout"
      end
      readers.each(&:join)
      status = t.value
      status = Struct.new(:exitstatus).new(124) if status.exitstatus.nil? # killed by signal (timeout)
    end
    [out, err, status]
  end

  # ---------------------------------------------------------------- cost

  def codex_cost(model_id, tokens)
    m = registry["models"].find { |x| x["id"] == model_id } || {}
    price = m["price_usd_per_mtok"] || {}
    return { "usd" => nil, "status" => "unavailable", "basis" => "no registry price for #{model_id.inspect}" } if price.empty?
    uncached = [tokens["input"].to_i - tokens["cached_input"].to_i, 0].max
    usd = (uncached * price["input"].to_f + tokens["cached_input"].to_i * (price["cache_read"] || price["input"]).to_f +
           tokens["output"].to_i * price["output"].to_f) / 1_000_000.0
    { "usd" => usd.round(6), "status" => "api_equivalent_estimate",
      "basis" => "registry list price x tokens at the standard tier; the served tier is unverified and subscription usage is billed differently" }
  end

  # ---------------------------------------------------------------- cost breakdown

  def text_metrics(text)
    t = text.to_s
    { "bytes" => t.bytesize, "words" => t.split.size, "est_tokens" => (t.bytesize / 4.0).ceil }
  end

  # Where a delegated task's cost goes, kept as four separate parts so none
  # hides in another. Preparation is split again: evaluation setup (hidden
  # references, overlays, fixtures) is paid once per task and reused by every
  # run, so it is not a delegation cost; the packet is what a host pays each
  # time it delegates. Figures that were not measured say so and are never
  # estimated here.
  def cost_breakdown(rec, task, packet:, final:)
    prep = task["preparation"] || {}
    timing = rec["timing"] || {}
    g = rec["grader"] || {}
    {
      "preparation" => {
        "reusable_eval_setup" => { "scope" => "once per task, amortised over its runs; not a per-delegation cost" }
          .merge(prep["eval_setup"] || { "status" => "not_recorded" }),
        "per_task_delegation" => { "scope" => "paid each time a host delegates this task",
                                   "packet" => text_metrics(packet).merge("requirement_items" => packet.to_s.scan(/^- [A-Z]\d+\. /).size),
                                   "authoring" => prep["packet_authoring"] || { "status" => "not_recorded" } }
      },
      "delegate_execution" => { "usd" => rec.dig("cost", "usd"), "status" => rec.dig("cost", "status"), "tokens" => rec["tokens"],
                                "wall_seconds" => timing["delegate_seconds"] || rec["wall_seconds"],
                                "wall_basis" => timing["delegate_seconds"] ? "delegate process only" : "whole trial (workspace export, delegate, grading); the split was not recorded" },
      "host_verification" => { "method" => "deterministic grader; no model call", "usd" => 0.0,
                               "grader_wall_seconds" => timing["grading_seconds"],
                               "reply" => text_metrics(final),
                               "findings_to_read" => g["findings"],
                               "findings_needing_adjudication" => g["unclassified_findings"],
                               "adjudication" => { "status" => "not_measured", "note" => "reading unclassified findings against the repository is manual and unmetered" } }.compact,
      "repair" => { "harness_loops" => rec.dig("repair_loops", "harness").to_i, "usd" => 0.0,
                    "delegate_internal_failed_tool_results" => rec.dig("repair_loops", "agent_failed_tool_results"),
                    "note" => "v0 runs a single attempt, so no repair dispatch exists to cost; failed tool results inside the run are already in delegate_execution" }
    }
  end

  # ---------------------------------------------------------------- record

  # The single validity rule: a run is model evidence only when every reason
  # below is absent. Invalid runs are kept and attributed to the observed model.
  def invalid_reasons(rec)
    reasons = []
    reasons << "exit status #{rec['exit_status'].inspect}" unless rec["exit_status"] == 0
    reasons += Array(rec.dig("accounting", "mismatches")).map { |k, v| "#{k} observed #{v['observed']} (requested #{v['requested']})" }
    reasons << "model unobserved" if rec.dig("observed", "model").nil?
    reasons << "effort unobserved" if rec.dig("observed", "effort").nil?
    audit = rec["isolation_audit"]
    if audit
      reasons << "external read observed" if audit.dig("external_read", "status") == "observed"
      reasons << "external write observed" if audit.dig("external_write", "status") == "observed"
      reasons << "reference data exposure observed" if audit.dig("reference_exposure", "status") == "observed"
    elsif rec.dig("contamination", "basis").to_s.start_with?("isolation-audit-")
      reasons << "isolation audit unavailable" if rec.dig("contamination", "suspect")
    elsif rec.dig("contamination", "suspect")
      reasons << "contamination suspected (legacy lexical audit)"
    end
    reasons << "workspace tree mismatch" unless rec["workspace_tree_ok"]
    reasons << "source repo changed" unless rec["source_repo_unchanged"]
    reasons << "codex isolation not verified" if rec["host"] == "codex" && !rec.dig("tool_profile", "isolation_verified")
    reasons
  end

  def valid_for_model_evidence?(rec) = invalid_reasons(rec).empty?

  # What produced a run: harness revision and digests of every input that
  # shapes the prompt, tools or grade.
  # Digests of what decides a grade: graders and the task's hidden data.
  def grader_fingerprint(task)
    files = { "graders.rb" => File.join(__dir__, "graders.rb"), "isolation_audit.rb" => File.join(__dir__, "isolation_audit.rb"),
              "task.yaml" => File.join(task.dir, "task.yaml") }
    files["spec_graders.rb"] = File.join(__dir__, "spec_graders.rb") if task["grader"] == "impl_spec"
    Dir.glob(File.join(task.hidden_dir, "*")).each { |f| files["hidden/#{File.basename(f)}"] = f }
    files.transform_values { |p| File.file?(p) ? Digest::SHA256.file(p).hexdigest[0, 16] : nil }
  end

  def harness_fingerprint(task, host)
    digest = ->(p) { File.file?(p) ? Digest::SHA256.file(p).hexdigest[0, 16] : nil }
    files = { "task.yaml" => File.join(task.dir, "task.yaml"), "packet" => task.packet_path,
              "role" => File.join(REPO, "agents", host == "codex" ? "codex" : "claude", "#{task['role']}#{host == 'codex' ? '.toml' : '.md'}"),
              "guard" => guard_path, "codex-delegate" => File.join(SCRIPTS, "codex-delegate"),
              "eval_support.rb" => __FILE__, "graders.rb" => File.join(__dir__, "graders.rb"),
              "isolation_audit.rb" => File.join(__dir__, "isolation_audit.rb") }
    files["spec_graders.rb"] = File.join(__dir__, "spec_graders.rb") if task["grader"] == "impl_spec"
    Dir.glob(File.join(task.hidden_dir, "*")).each { |f| files["hidden/#{File.basename(f)}"] = f }
    { "git_sha" => (Open3.capture2("git", "-C", REPO, "rev-parse", "HEAD").first.strip rescue nil),
      "dirty" => !(Open3.capture2("git", "-C", REPO, "status", "--porcelain", "--", ".", ":!evals/results").first.strip.empty? rescue true),
      "digests" => files.transform_values { |p| digest.call(p) } }
  end

  # Runs are written to, and read from, the store when one is attached.
  def results_dir = File.join(store || ROOT, "results")
end

# frozen_string_literal: true

# No-model verification of the eval harness itself: workspace reset, hidden
# data isolation, grader sensitivity, evidence accounting and the eval tool
# profile, exercised on the built-in example task and on every task of an
# attached evidence store. Checks that contain a private task's reference
# answers live in that store. Used by bin/verify and the test suite; makes
# no model calls.

require_relative "eval_support"
require_relative "graders"
require_relative "summary"

module Evals
  module Verify
    module_function

    Check = Struct.new(:area, :name, :pass, :detail)

    def checks
      @checks = []
      @skips = []
      frozen_tasks
      adjudication_files
      workspace_reset
      hidden_isolation
      isolation_audit
      example_review_grader
      accounting
      tool_profile
      private_task_checks
      @checks
    end

    def check(area, name, pass, detail = "") = (@checks << Check.new(area, name, !!pass, detail.to_s))

    # Things that could not be checked here, with the reason. Printed by
    # bin/verify; never counted as passes.
    def skips = (@skips ||= [])
    def skip(what) = (skips << what)

    # Tasks whose base tree can be built on this machine. A task taken from a
    # source repository that is not configured or not present is skipped by
    # name, never silently.
    def each_available_task
      Evals.task_ids.each do |id|
        task = Evals.load_task(id)
        unless task.fixture?
          path = (Evals.repo_path(task["repo"]) rescue nil)
          unless path && File.directory?(File.join(path, ".git"))
            skip("#{id}: source repository #{task['repo'].inspect} is not available on this machine")
            next
          end
        end
        yield task
      end
    end

    # Checks that belong to the tasks in a private evidence store live in the
    # store (fixtures/verify_private.rb), because they contain reference
    # answers. Without a store they are skipped, and said to be.
    def private_task_checks
      file = Evals.store && File.join(Evals.store, "fixtures", "verify_private.rb")
      if file && File.file?(file)
        require file
        private_checks
      else
        skip(Evals.store ? "private-task verification: #{file} is missing" : "private-task verification: no evidence store is attached (set EVAL_STORE or evals/config.local.yaml)")
      end
    end

    # The built-in example task: the review grader credits a finding only
    # where the defect is, records severity and classes, and passes or fails
    # on the verdict.
    def example_review_grader
      task = Evals.load_task("example-review")
      reply = ->(verdict, fs) { "review\n```json\n#{JSON.generate({ "verdict" => verdict, "findings" => fs })}\n```" }
      f = ->(axis, sev, line, req, s) { { "axis" => axis, "severity" => sev, "path" => "scripts/rotate-log.sh", "line" => line, "requirement" => req, "summary" => s } }
      missing = f.call("SPEC", "blocking", 28, "X3", "A missing FILE is created with touch and rotated, and the script exits 0 where X3 requires a refusal.")
      quoting = f.call("STANDARDS", "suggestion", 28, nil, "The path is unquoted, so a name containing a space is split into two words.")
      with_ws(task) do |ws, _|
        check("example", "example-review: the packet's evidence holds for the workspace (bash -n and git diff --check both clean)",
              system("bash", "-n", File.join(ws, "scripts", "rotate-log.sh")) && Open3.capture2("git", "-C", ws, "diff", "--check", "HEAD").last.success?, "")
        full = Graders.review(task, reply.call("CHANGES_REQUESTED", [missing, quoting]), ws)
        check("example", "example-review: a complete review passes, with recall 1, the requirement cited and each severity recorded",
              full["pass"] && full["critical_recall"] == 1.0 && full["total_recall"] == 1.0 && full["spec_findings_cite_requirement"].values.all? &&
              full["defect_severity"] == { "E1-missing-file-not-refused" => "blocking", "E2-unquoted-path" => "suggestion" }, full.slice("critical_recall", "defect_severity"))
        approved = Graders.review(task, reply.call("APPROVED", [quoting]), ws)
        check("example", "example-review: approving the change fails and names the missed critical defect",
              !approved["pass"] && approved["critical_missed"] == ["E1-missing-file-not-refused"] && approved["verdict_basis"] == "unjustified", approved["critical_missed"])
        far = Graders.review(task, reply.call("CHANGES_REQUESTED", [missing.merge("line" => 5), missing.merge("line" => nil)]), ws)
        check("example", "example-review: the right words at the wrong line, or with no line, earn no defect credit",
              far["defects_found"].empty? && !far["pass"], far["finding_classes"])
        mixed = Graders.review(task, reply.call("CHANGES_REQUESTED", [missing, missing.merge("axis" => "STANDARDS", "requirement" => nil),
                                                                        f.call("STANDARDS", "suggestion", 1, nil, "No tests cover the new script."),
                                                                        f.call("STANDARDS", "uncertainty", 1, nil, "The script could not be run in this sandbox."),
                                                                        f.call("STANDARDS", "blocking", 40, nil, "The loop variable should be renamed.")]), ws)
        check("example", "example-review: a repeat is a duplicate, a coverage remark is valid but out of scope, a sandbox remark is a process note, and an unknown blocking finding is left for a human",
              mixed["finding_classes"].values_at("defect", "duplicate", "valid_out_of_scope", "process_note", "unclassified") == [1, 1, 1, 1, 1] &&
              mixed["incorrect_findings"].zero? && mixed["blocking_non_defect"].size == 1, mixed["finding_classes"])
        check("example", "example-review: a reply with no JSON block is a format failure", !Graders.review(task, "no json here", ws)["format_ok"], "")
      end
    end

    def with_ws(task)
      Dir.mktmpdir("eval-verify-") do |tmp|
        ws, tree = Evals.prepare_workspace(task, tmp)
        yield File.realpath(ws), tree
      end
    end

    def workspace_reset
      each_available_task do |task|
        id = task.id
        trees = []
        digests = []
        2.times do
          with_ws(task) do |ws, tree|
            trees << tree
            digests << Evals.file_digests(ws)
            if task.fixture?
              # self-contained: nothing outside the task to compare with
            elsif task.scope != ["."]
              task.scope.each do |s|
                src = Evals.git(Evals.repo_path(task["repo"]), "rev-parse", "#{task['sha']}:#{s}").strip
                got = Evals.git(ws, "rev-parse", "HEAD:#{s}").strip
                check("reset", "#{id}: exported #{s} equals source tree at SHA", src == got, "#{got[0, 12]} vs #{src[0, 12]}")
              end
            else
              src = Evals.git(Evals.repo_path(task["repo"]), "rev-parse", "#{task['sha']}^{tree}").strip
              check("reset", "#{id}: exported tree equals source commit tree", src == tree, tree[0, 12])
            end
            check("reset", "#{id}: workspace has one commit and no future history",
                  Evals.git(ws, "rev-list", "--count", "HEAD").strip == "1", "")
            log = Evals.git(ws, "log", "--format=%an%n%ae%n%cn%n%ce%n%s%n%b").downcase
            hints = [id, "seeded", "hidden", "eval", "task"].select { |w| log.include?(w.downcase) }
            check("hidden", "#{id}: git log carries no task hints", hints.empty?, hints.join(","))
            overlay_from_history(task, ws) if task["overlay_sha"]
          end
        end
        check("reset", "#{id}: two fresh exports are identical and match the pinned tree",
              trees.uniq == [task["workspace_tree"]] && digests.uniq.size == 1, trees.uniq.map { |t| t[0, 12] }.join(","))
      end
    end

    # A change taken from history (overlay_sha): the working tree must equal
    # the source repository's tree at that commit for every scope entry, the
    # change must be uncommitted, and no object from the later commit may be
    # reachable.
    def overlay_from_history(task, ws)
      src = Evals.repo_path(task["repo"])
      Dir.mktmpdir("eval-verify-index-") do |tmp|
        env = { "GIT_INDEX_FILE" => File.join(tmp, "index") }
        Evals.git(ws, "add", "-A", env: env)
        tree = Evals.git(ws, "write-tree", env: env).strip
        same = task.scope.all? do |sc|
          Evals.git(ws, "rev-parse", "#{tree}:#{sc}").strip == Evals.git(src, "rev-parse", "#{task['overlay_sha']}:#{sc}").strip
        end
        check("reset", "#{task.id}: the reviewed change equals the source tree at the overlay commit and matches the pinned overlay tree",
              same && tree == task["overlay_tree"], tree[0, 12])
      end
      changed = Evals.git(ws, "status", "--porcelain").lines.size
      reachable = (Evals.git(ws, "cat-file", "-t", task["overlay_sha"]) rescue nil)
      check("hidden", "#{task.id}: the change is uncommitted (#{changed} paths) and the later commit is not reachable in the workspace",
            changed.positive? && Evals.git(ws, "rev-list", "--count", "HEAD").strip == "1" && reachable.nil?, "")
    end

    # Every task that declares a version has its freeze file, lists its own
    # packet, task file and hidden list and the grader, and still matches
    # every recorded hash. bin/run and bin/regrade refuse a task that fails.
    def frozen_tasks
      Evals.task_ids.map { |id| Evals.load_task(id) }.select { |t| t["task_version"] }.each do |t|
        file = Evals.data_path("analysis/#{t["task_family"] || t.id}-freeze-v#{t["task_version"]}.json")
        listed = File.file?(file) ? Hash(JSON.parse(File.read(file))["sha256"]).keys : []
        needed = ["tasks/#{t.id}/packet.md", "tasks/#{t.id}/task.yaml", "hidden/#{t.id}/defects.yaml", "lib/graders.rb"]
        changed = Evals.frozen_mismatches(t)
        check("frozen", "#{t.id}: version #{t['task_version']} has its freeze file; packet, task file, hidden list and grader are listed and match their hashes",
              changed.empty? && (needed - listed).empty?, (changed + (needed - listed)).join(", "))
      end
    end

    # Human rulings on individual findings (hidden/<task>/adjudications.yaml)
    # must be auditable and must not reach outside the frozen ground truth:
    # a known class, the finding's text, a reason and a date on every entry,
    # and for a defect or a valid blocking finding an id from the task's own
    # frozen lists.
    ADJUDICATION_CLASSES = %w[defect duplicate valid_blocking incorrect process_note valid_out_of_scope].freeze
    def adjudication_problems(entries, ref)
      ids = { "defect" => Array(ref["defects"]), "valid_blocking" => Array(ref["other_blocking"]) }.transform_values { |l| l.map { |x| x["id"] } }
      Array(entries).each_with_index.filter_map do |e, i|
        next "entry #{i}: not a mapping" unless e.is_a?(Hash)
        next "entry #{i}: unknown class #{e['class'].inspect}" unless ADJUDICATION_CLASSES.include?(e["class"])
        next "entry #{i}: summary, reason and date are required" if %w[summary reason date].any? { |k| e[k].to_s.strip.empty? }
        next "entry #{i}: #{e['class']} needs an id from the frozen list (got #{e['id'].inspect})" if ids[e["class"]] && !ids[e["class"]].include?(e["id"])
      end
    end

    def adjudication_files
      good = [{ "summary" => "s", "class" => "valid_out_of_scope", "reason" => "r", "date" => "2026-10-01" }]
      ref = { "defects" => [{ "id" => "T1" }], "other_blocking" => [{ "id" => "B1" }] }
      bad = [good[0].merge("class" => "valid"), good[0].merge("reason" => ""), good[0].merge("class" => "defect", "id" => "T9"),
             good[0].merge("class" => "valid_blocking"), "text"]
      check("adjudication", "a ruling needs a known class, the finding text, a reason, a date, and for a defect or valid blocking finding an id from the frozen lists",
            adjudication_problems(good, ref).empty? && adjudication_problems(bad, ref).size == bad.size &&
            adjudication_problems([good[0].merge("class" => "defect", "id" => "T1"), good[0].merge("class" => "valid_blocking", "id" => "B1")], ref).empty?, "")
      Evals.hidden_roots.flat_map { |h| Dir.glob(File.join(h, "*", "adjudications.yaml")) }.sort.each do |f|
        ref = YAML.safe_load(File.read(File.join(File.dirname(f), "defects.yaml")))
        problems = adjudication_problems(YAML.safe_load(File.read(f)), ref)
        check("adjudication", "#{File.basename(File.dirname(f))}: every recorded ruling is well formed", problems.empty?, problems.first.to_s)
      end
    end

    def hidden_isolation
      each_available_task do |task|
        id = task.id
        packet = task.packet_text
        leaks = ["evals/hidden", "HIDDEN", "seeded", *Evals.hidden_roots]
        case task["grader"]
        when "explore"
          ref = YAML.safe_load(File.read(File.join(task.hidden_dir, "expected.yaml")))
          leaks += Array(ref["expected"]).map { |e| e["path"] } + Array(ref["acceptable"])
        when "review"
          ref = YAML.safe_load(File.read(File.join(task.hidden_dir, "defects.yaml")))
          leaks += %w[defects mechanical restatements other_blocking incorrect process_notes acceptable].flat_map { |k| Array(ref[k]) }.map { |d| d["id"] }
        end
        found = leaks.select { |l| !l.to_s.empty? && packet.include?(l) }
        check("hidden", "#{id}: packet contains no hidden reference data", found.empty?, found.first(3).join(" | "))
        with_ws(task) do |ws, _|
          hidden_in_ws = Dir.glob("**/*", base: ws).select { |p| p.start_with?("evals/", "hidden/") }
          check("hidden", "#{id}: workspace contains no evals/ or hidden/ tree", hidden_in_ws.empty?, hidden_in_ws.first(3).join(","))
        end
      end
    end

    # Isolation audit (lib/isolation_audit.rb). Every false-positive pattern
    # found in practice is a fixture that must stay clean, and
    # genuine external reads, writes and reference exposure must fail.
    CLAUDE_ENFORCED = { shell_home_read_denied: true, file_tool_home_denied: true,
                        shell_write_roots: %w[workspace scratch device], file_tool_write_roots: %w[workspace] }.freeze
    CLAUDE_UNENFORCED = { shell_home_read_denied: false, file_tool_home_denied: false, shell_write_roots: nil, file_tool_write_roots: nil }.freeze
    CODEX_WRITE = { shell_home_read_denied: false, file_tool_home_denied: false,
                    shell_write_roots: %w[workspace scratch device], file_tool_write_roots: %w[workspace scratch device] }.freeze
    IMPL_POLICY = { "scratch_writes" => true, "cwd_independence" => true }.freeze
    RO_POLICY = { "scratch_writes" => false, "cwd_independence" => false }.freeze

    def isolation_audit
      home = File.realpath(Dir.home)
      # The fixtures describe a repository at ~/claude-skills with its evals
      # tree as the protected locations, wherever this checkout really is.
      fixture_repo = File.join(home, "claude-skills")
      fixture_roots = [fixture_repo, File.join(fixture_repo, "evals")]
      ws = File.realpath(Dir.mktmpdir("eval-audit-"))
      sh = ->(cmd, out: "", error: false) { { tool: "Bash", input: { "command" => cmd }, output: out, error: error } }
      ex = lambda do |cmd, out: "", code: 0|
        { tool: "exec", input: { "command" => "/bin/zsh -lc #{Shellwords.escape(cmd)}" }, output: out, exit_code: code, error: code != 0 }
      end
      run = lambda do |host, calls, enforce, policy = IMPL_POLICY, canaries: []|
        IsolationAudit.audit(host: host, calls: calls.each_with_index.map { |c, i| c.merge(index: i) }, workspace: ws, policy: policy,
                             enforce: enforce, canaries: canaries, protected_roots: fixture_roots)
      end
      clean = ->(a) { !IsolationAudit.suspect?(a) }
      read_status = ->(a) { a.dig("external_read", "status") }
      readme = "1. **Scaffold:**\n   ```bash\n   cd ~/claude-skills\n   ~/claude-skills/scripts/new-skill.sh my-skill\n   ```\n"
      py_edit = "python3 - <<'PY'\np='README.md'\ns=open(p).read()\nopen(p,'w').write(s.replace('x', \"\"\"#{readme}\"\"\"))\nPY"

      # --- lexical patterns that are not access (regression fixtures)
      a = run.call("claude-code", [{ tool: "Write", input: { "file_path" => "#{ws}/README.md", "content" => readme }, output: "ok", error: false }],
                   CLAUDE_ENFORCED)
      check("isolation", "README text with ~/ written by a file tool is not an access", clean.call(a) && read_status.call(a) == "none", read_status.call(a))
      a = run.call("claude-code", [sh.call("cat > README.md <<'EOF'\n#{readme}EOF\n#{py_edit}")], CLAUDE_ENFORCED)
      check("isolation", "README text with ~/ in a heredoc or a Bash-run Python edit is not contamination (home unreadable: prevented at most)",
            clean.call(a) && read_status.call(a) == "none", a["external_read"].inspect[0, 200])
      a = run.call("codex", [ex.call(py_edit)], CODEX_WRITE)
      check("isolation", "the same Python edit under Codex (no read enforcement) is recorded as unknown, never invalidating",
            clean.call(a) && read_status.call(a) == "unknown", read_status.call(a))
      grep = 'grep -rln "PUBLIC_APP_MODE\|from \"../lib/app-mode\"" --include="*.ts" --include="*.tsx" app'
      a = run.call("claude-code", [sh.call(grep)], CLAUDE_ENFORCED, RO_POLICY)
      b = run.call("codex", [ex.call("#{grep}; rg -n '\.\./lib/app-mode' app")], CODEX_WRITE, RO_POLICY)
      check("isolation", "a grep/rg pattern containing ../ is a pattern, not a path",
            [a, b].all? { |x| clean.call(x) && read_status.call(x) == "none" }, [a, b].map(&read_status).join(","))
      a = run.call("claude-code", [sh.call("N=scripts/new-skill.sh; bash $N ../evil; echo $?; cd /; #{ws}/scripts/new-skill.sh ../evil; cd #{ws}; ./x '../../etc'")],
                   CLAUDE_ENFORCED)
      b = run.call("codex", [ex.call("scripts/new-skill.sh ../evil; (cd / && #{ws}/scripts/new-skill.sh ../evil)")], CODEX_WRITE)
      check("isolation", "hostile input ../evil passed to the task's own script is data",
            [a, b].all? { |x| clean.call(x) && read_status.call(x) == "none" }, [a, b].map { |x| x["external_read"]["events"].map { |e| e["path"] } }.inspect)
      scratch = "S=$TMPDIR/nsk; rm -rf $S; mkdir -p $S; cp -R scripts $S/; cd $S; git init -q .\n" \
                "t(){ echo \"--- $*\"; \"$@\"; }\ncd /; t $S/scripts/new-skill.sh alpha; ls $S/alpha; cat $S/alpha/SKILL.md | head -3; ln -s /nowhere $S/dangling"
      a = run.call("claude-code", [sh.call(scratch)], CLAUDE_ENFORCED)
      check("isolation", "cd / then running a scratch copy is a permitted cwd escape for a cwd-independence task, not contamination",
            clean.call(a) && a.dig("cwd_escape", "occurred") && a.dig("cwd_escape", "permitted_by_task") && read_status.call(a) == "none" &&
            a.dig("external_write", "status") == "none", a.slice("cwd_escape", "external_write").inspect[0, 200])
      a = run.call("claude-code", [sh.call("cd /; ls; cd $TMPDIR && ls -ld .; cd #{ws} && rg -n x .")], CLAUDE_ENFORCED, RO_POLICY)
      check("isolation", "a cwd escape in a task without cwd independence is recorded as unpermitted and does not invalidate by itself",
            clean.call(a) && a.dig("cwd_escape", "occurred") && !a.dig("cwd_escape", "permitted_by_task"), a["cwd_escape"].inspect[0, 120])
      a = run.call("claude-code", [sh.call(scratch)], CLAUDE_ENFORCED, RO_POLICY)
      check("isolation", "scratch writes that the task policy does not allow are an external write violation",
            !clean.call(a) && a.dig("external_write", "status") == "observed", a.dig("external_write", "status"))
      tmp = "test_root=$(mktemp -d /tmp/new-skill-test.XXXXXX)\n(cd / && cp -R #{ws}/scripts \"$test_root\"/ && " \
            "\"$test_root/scripts/new-skill.sh\" demo && cat \"$test_root/demo/SKILL.md\")\nrm -rf \"$test_root\""
      a = run.call("codex", [ex.call(tmp)], CODEX_WRITE)
      check("isolation", "harness temp-directory execution (mktemp under /tmp) is allowed scratch use",
            clean.call(a) && read_status.call(a) == "none" && a.dig("external_write", "status") == "none" && a.dig("scratch", "writes").positive?,
            a["scratch"].inspect)

      # --- genuine access that must fail
      a = run.call("codex", [ex.call("sed -n '1,260p' #{home}/.codex/skills/engineering-workflow/SKILL.md; sed -n '1,80p' README.md",
                                     out: "---\nname: x\n")], CODEX_WRITE)
      check("isolation", "codex reading the user's ~/.codex skill files (exit 0) is an observed external read",
            !clean.call(a) && read_status.call(a) == "observed", read_status.call(a))
      a = run.call("codex", [ex.call("cat #{fixture_repo}/evals/hidden/example-review/defects.yaml")], CODEX_WRITE, RO_POLICY)
      b = run.call("codex", [ex.call("cat ../../../../../../../..#{fixture_repo}/evals/hidden/example-review/defects.yaml")], CODEX_WRITE)
      check("isolation", "reading hidden grader data, directly or via ../ escapes, is an observed external read of a protected location",
            [a, b].all? { |x| !clean.call(x) && x["external_read"]["events"].any? { |e| e["location"] == "protected" } }, [a, b].map(&read_status).join(","))
      a = run.call("codex", [ex.call("git -C #{fixture_repo} log --oneline -5")], CODEX_WRITE)
      b = run.call("codex", [ex.call("cd ~/claude-skills && git log -p -3")], CODEX_WRITE)
      check("isolation", "reading the real source repo's history (git -C or cd ~) is an observed external read", !clean.call(a) && !clean.call(b),
            [a, b].map(&read_status).join(","))
      a = run.call("codex", [ex.call("rg -n 'expected_verdict' /")], CODEX_WRITE)
      check("isolation", "a recursive search from / reaches the home and counts as an external read", !clean.call(a), read_status.call(a))
      a = run.call("claude-code", [{ tool: "Read", input: { "file_path" => "~/claude-skills/README.md" }, output: "# Skills", error: false }], CLAUDE_UNENFORCED)
      b = run.call("claude-code", [{ tool: "Read", input: { "file_path" => "~/claude-skills/README.md" }, output: "denied by your permission settings",
                                     error: true }], CLAUDE_ENFORCED)
      c = run.call("claude-code", [sh.call("cat ~/claude-skills/README.md", out: "# Skills")], CLAUDE_UNENFORCED)
      check("isolation", "a file-tool or unsandboxed Bash read of home data that succeeded is observed; a denied one is prevented",
            !clean.call(a) && !clean.call(c) && clean.call(b) && b["external_read"]["events"].first["status"] == "prevented",
            [a, b, c].map(&read_status).join(","))
      task = Evals.load_task("example-review")
      canaries = IsolationAudit.canaries_for(task)
      leak = canaries.find { |x| x[:file].include?("defects.yaml") }
      a = run.call("claude-code", [sh.call("cat notes.txt", out: "notes\n#{leak && leak[:line]}\n")], CLAUDE_ENFORCED, RO_POLICY, canaries: canaries)
      b = run.call("claude-code", [sh.call("cat scripts/rotate-log.sh", out: File.read(File.join(task.dir, "overlay", "scripts", "rotate-log.sh")))],
                   CLAUDE_ENFORCED, RO_POLICY, canaries: canaries)
      check("isolation", "hidden reference content in model-visible output is observed exposure whatever the path; workspace content is not",
            leak && !clean.call(a) && a.dig("reference_exposure", "status") == "observed" && clean.call(b), "#{canaries.size} canaries")
      a = run.call("codex", [ex.call("echo x > ~/leak.txt")], CODEX_WRITE.merge(shell_write_roots: nil))
      b = run.call("codex", [ex.call("echo x > ~/leak.txt", code: 1)], CODEX_WRITE)
      c = run.call("claude-code", [sh.call("mkdir -p /tmp/x && echo y > /tmp/x/f")], CLAUDE_ENFORCED, RO_POLICY)
      check("isolation", "an unenforced external write that succeeded is observed; an enforced one is prevented; scratch writes outside policy are not allowed",
            !clean.call(a) && a.dig("external_write", "status") == "observed" && clean.call(b) &&
            c["external_write"]["events"].any? { |e| e["location"] == "scratch" }, [a, b, c].map { |x| x.dig("external_write", "status") }.join(","))
      a = run.call("codex", [ex.call(%q(python3 -c "print(open('/Users/someone/.ssh/config').read())"))], CODEX_WRITE)
      check("isolation", "an opaque program naming a host path is unknown (recorded for a human), not observed",
            clean.call(a) && read_status.call(a) == "unknown", read_status.call(a))
      m = run.call("codex", [ex.call("echo ~/ $HOME ../x")], CODEX_WRITE)
      check("isolation", "lexical path markers are diagnostic only", clean.call(m) && m.dig("path_string_mentions", "count") >= 3,
            m["path_string_mentions"].inspect[0, 120])

      # --- must-fail cases from the independent review (round 1)
      observed = ->(a) { !clean.call(a) && read_status.call(a) == "observed" }
      skill = "#{home}/claude-skills/scripts/new-skill.sh"
      a = run.call("codex", [ex.call("bash -x #{skill} demo")], CODEX_WRITE)
      b = run.call("codex", [ex.call("~/claude-skills/scripts/new-skill.sh --help")], CODEX_WRITE)
      c = run.call("codex", [ex.call("sh -v ~/x.sh")], CODEX_WRITE)
      check("isolation", "running a program file from a host path reads it (bash -x, direct exec, sh -v)",
            [a, b, c].all?(&observed) && a["executed_outside"].any?, [a, b, c].map(&read_status).join(","))
      gits = ["git clone ~/claude-skills /tmp/c && git -C /tmp/c log -p", "git fetch ~/claude-skills", "git --git-dir=$HOME/claude-skills/.git log -p",
              "git --git-dir #{home}/claude-skills/.git log", "GIT_DIR=~/claude-skills/.git git log", "git --work-tree=~/claude-skills status"]
      res = gits.map { |g| run.call("codex", [ex.call(g)], CODEX_WRITE) }
      check("isolation", "git clone/fetch sources, --git-dir, --work-tree and GIT_DIR pointing at the real repo are observed reads",
            res.all?(&observed), gits.zip(res.map(&read_status)).reject { |_, s| s == "observed" }.inspect)
      a = run.call("codex", [ex.call("cat evals/hidden/example-review/defects.yaml").merge(workdir: fixture_repo)], CODEX_WRITE)
      b = run.call("codex", [ex.call("git log -p -2").merge(workdir: "~/claude-skills")], CODEX_WRITE)
      check("isolation", "a Codex command whose workdir is the real repo is judged there (observed read, cwd escape recorded)",
            observed.call(a) && observed.call(b) && a.dig("cwd_escape", "occurred"), [a, b].map(&read_status).join(","))
      perm = "rg: #{home}/Library/Mail: Operation not permitted (os error 1)\n#{home}/claude-skills/scripts/new-skill.sh:3:# Scaffold\n"
      a = run.call("codex", [ex.call("rg -n new-skill ~", out: perm, code: 2)], CODEX_WRITE)
      b = run.call("codex", [ex.call("find / -name defects.yaml -exec cat {} \\;", out: "find: /Library/x: Permission denied\n", code: 1)], CODEX_WRITE)
      c = run.call("codex", [ex.call("cat #{home}/.codex/config.toml; rg -n zzz .", out: "model = \"x\"\n", code: 1)], CODEX_WRITE)
      check("isolation", "a recursive read with permission errors and a non-zero exit is still observed; a later failing command does not hide a read",
            [a, b, c].all?(&observed), [a, b, c].map(&read_status).join(","))
      a = run.call("codex", [ex.call("cat #{home}/.codex/nope.toml", out: "cat: #{home}/.codex/nope.toml: No such file or directory\n", code: 1)], CODEX_WRITE)
      check("isolation", "a read whose error names that exact path failed (not observed)", clean.call(a) && read_status.call(a) == "none", read_status.call(a))
      firm = "/System/Volumes/Data#{home}/claude-skills/README.md"
      paths = [firm, home.sub("/Users/", "/users/").upcase.sub("/USERS/", "/users/") + "/claude-skills/README.md", "/U*/*/claude-skills/evals/hidden/*"]
      res = paths.map { |pth| run.call("codex", [ex.call("cat #{pth}")], CODEX_WRITE) }
      check("isolation", "the data-volume firmlink, a different case and a glob before the home all resolve to the home", res.all?(&observed),
            paths.zip(res.map(&read_status)).inspect)
      a = run.call("codex", [ex.call("echo ~/.codex/skills/x/SKILL.md | xargs cat")], CODEX_WRITE)
      b = run.call("claude-code", [sh.call("echo ~/.codex/x | xargs cat")], CLAUDE_ENFORCED)
      check("isolation", "xargs-supplied operands are unknown under Codex and contained under Claude's home denial, never dropped",
            read_status.call(a) == "unknown" && b["external_read"]["events"].any? { |e| e["status"] == "contained" }, [a, b].map(&read_status).join(","))
      subst = ["rev <<< \"$(cat ~/.codex/config.toml)\"", "echo ${X:-$(cat ~/.codex/config.toml)}", "case \"$(cat ~/.codex/config.toml)\" in x) echo;; esac",
               "cat <<EOF\n$(cat ~/.codex/config.toml)\nEOF", "ln -s ~/claude-skills link; cat link/README.md", "cp -R ~/claude-skills /tmp/c",
               "[[ \"$(<~/.codex/config.toml)\" == x && -n y ]] && echo ok"]
      res = subst.map { |x| run.call("codex", [ex.call(x)], CODEX_WRITE) }
      check("isolation", "reads inside here-strings, ${X:-$(...)}, case subjects, unquoted heredocs, [[ ]] tests, through a created symlink, and cp sources are observed",
            res.all?(&observed), subst.zip(res.map(&read_status)).reject { |_, s| s == "observed" }.inspect)
      a = run.call("codex", [ex.call("cat <<'EOF'\n$(cat ~/.codex/config.toml)\nEOF")], CODEX_WRITE)
      check("isolation", "a quoted heredoc body is data (no expansion)", clean.call(a) && read_status.call(a) == "none", read_status.call(a))
      res = ["eval \"$X\"", "bash -c \"$X\"", "mytool --config=#{home}/.codex/config.toml"].map { |x| run.call("codex", [ex.call(x)], CODEX_WRITE) }
      check("isolation", "unresolved eval/bash -c and --opt=/host/path operands are unknown, never dropped", res.all? { |x| read_status.call(x) == "unknown" },
            res.map(&read_status).join(","))
      a = run.call("claude-code", [{ tool: "Read", input: { "file_path" => "~/claude-skills/README.md" }, output: "# Skills", error: false }], CLAUDE_ENFORCED)
      b = run.call("claude-code", [{ tool: "Write", input: { "file_path" => "#{home}/leak.txt", "content" => "x" }, output: "ok", error: false }], CLAUDE_ENFORCED)
      check("isolation", "a file-tool success contradicting the deny rules is observed (results beat assumptions)",
            observed.call(a) && b.dig("external_write", "status") == "observed", [read_status.call(a), b.dig("external_write", "status")].join(","))
      a = run.call("codex", [ex.call("cat #{home}/.codex/config.toml").merge(rejected: true, error: true)], CODEX_WRITE)
      check("isolation", "a command the Codex sandbox rejected never ran: prevented", clean.call(a) && read_status.call(a) == "none", read_status.call(a))
      a = run.call("codex", [ex.call("ls")], CODEX_WRITE)
      a2 = IsolationAudit.audit(host: "codex", calls: [ex.call("ls").merge(index: 0)], workspace: ws, policy: IMPL_POLICY, enforce: CODEX_WRITE,
                                protected_roots: fixture_roots, coverage: { "complete" => false, "notes" => ["unaudited tool x"] })
      check("isolation", "incomplete Codex trace coverage makes the read dimension unknown", read_status.call(a) == "none" && read_status.call(a2) == "unknown", "")
      bare = canaries.select { |x| x[:line].sub(/\A-\s+/, "").delete("'\"").match?(%r{\A[\w.@/-]+\z}) }
      check("isolation", "bare workspace paths from answer files are not canaries", bare.empty?, bare.first(2).inspect)

      # --- round-2 review: git search patterns and pathspecs are not reads
      gits = ['git grep "~/claude-skills"', "git grep -i \"#{home}/x\" -- scripts", 'git log -S "~/x" --oneline', "git log --grep=~/claude-skills",
              "git log -- ~/x", "git diff -- #{home}/claude-skills", "cd / && git status --short"]
      res = gits.map { |g| run.call("codex", [ex.call(g)], CODEX_WRITE) }
      check("isolation", "git search patterns, out-of-repo pathspecs and git in / are never observed reads (pathspecs: unknown at most)",
            res.all? { |x| clean.call(x) }, gits.zip(res.map(&read_status)).inspect)
      a = run.call("claude-code", [sh.call("cat /System/Volumes/Data#{home}/.codex/config.toml", out: "model = \"x\"\n")], CLAUDE_ENFORCED)
      b = run.call("claude-code", [sh.call("cat #{home}/.codex/config.toml", out: "model = \"x\"\n")], CLAUDE_ENFORCED)
      check("isolation", "Claude's sandbox assumption covers literal home paths only; an alias spelling is judged by its output",
            observed.call(a) && clean.call(b) && b["external_read"]["events"].first["status"] == "prevented", [a, b].map(&read_status).join(","))
      paths = ["/.nofollow#{home}/.codex/skills/x/SKILL.md", "/.resolve/1#{home}/.codex/config.toml", "/system/volumes/data#{home}/.codex/config.toml"]
      res = paths.map { |pth| run.call("codex", [ex.call("cat #{pth}", out: "x\n")], CODEX_WRITE) }
      v = run.call("codex", [ex.call("cat /.vol/16777220/12345", out: "x\n")], CODEX_WRITE)
      check("isolation", "/.nofollow, /.resolve and lower-case firmlink spellings reach the home; /.vol reads are unknown",
            res.all?(&observed) && read_status.call(v) == "unknown", paths.zip(res.map(&read_status)).inspect + " vol=#{read_status.call(v)}")
      a = run.call("codex", [ex.call("PATH=~/claude-skills/scripts:$PATH new-skill.sh --help")], CODEX_WRITE)
      b = run.call("codex", [ex.call("export PATH=#{home}/bin:$PATH; mytool")], CODEX_WRITE)
      check("isolation", "a command found through a PATH entry in the home is a possible read (unknown), not dropped",
            [a, b].all? { |x| read_status.call(x) == "unknown" }, [a, b].map(&read_status).join(","))
      a = run.call("codex", [ex.call("test -f ~/.codex/config.toml && echo yes; [ -d #{home}/claude-skills ]")], CODEX_WRITE)
      check("isolation", "existence probes (test -f, [ -d ]) are possible reads, never observed", clean.call(a) && read_status.call(a) == "unknown", read_status.call(a))
      logdir = File.join(ws, "codex-log-fixture")
      FileUtils.mkdir_p(logdir)
      t = "2026-01-01T00:00:00.000001Z  INFO codex_otel.log_only: event.name=\"codex.tool_result\" tool_result_seq=1 tool_name=exec_command " \
          "tool_namespace=functions call_id=exec-00000000-0000-4000-8000-000000000001 duration_ms=87 "
      tail = "\n mcp_server= mcp_server_origin= event.timestamp=2026-01-01T00:00:00.000Z conversation.id=00000000-0000-7000-8000-000000000002 " \
             "app.version=0.159.2 auth_mode=\"AUTH\" originator=codex_exec user.account_id=\"ACCOUNT\" user.email=\"EMAIL\" terminal.type=unknown " \
             "model=gpt-5.6-terra slug=gpt-5.6-terra\n" \
             "2026-01-01T00:00:00.000002Z  INFO codex_otel.trace_safe: event.name=\"codex.tool_result\" tool_result_seq=1 tool_name=exec_command " \
             "success=true output_truncated=false arguments_length=312 output_length=0\n"
      cmd1 = { "cmd" => "echo ' output=x'; cat README.md", "workdir" => fixture_repo }
      File.write(File.join(logdir, "codex.log"),
                 "#{t}success=true output_truncated=false agent_name=/root arguments=#{JSON.generate(cmd1)} output=Chunk ID: aaaaaa\nWall time: 0.0000 seconds\n" \
                 "Process exited with code 0\nOriginal token count: 3\nOutput:\n# Skills#{tail}" \
                 "#{t}success=false arguments=#{JSON.generate('cmd' => 'cat ~/.codex/config.toml', 'workdir' => ws)} " \
                 "output=exec_command failed: CreateProcess { message: \"Rejected(\\\"x\\\")\" }\n")
      File.write(File.join(logdir, "events.jsonl"), [{ "type" => "item.completed", "item" => { "type" => "command_execution", "command" => "x", "aggregated_output" => "", "exit_code" => 0 } }].map { |h| JSON.generate(h) }.join("\n"))
      calls, cov = IsolationAudit.codex_calls(logdir)
      execs = calls.select { |c| c[:tool] == "exec" }
      parsed = execs.size == 2 && execs[0][:workdir] == fixture_repo && execs[0][:input]["command"] == cmd1["cmd"] && execs[0][:output].include?("# Skills") &&
               !execs[0][:rejected] && execs[1][:rejected] && cov["complete"]
      a = IsolationAudit.audit(host: "codex", calls: calls, workspace: ws, policy: IMPL_POLICY, enforce: CODEX_WRITE,
                               protected_roots: fixture_roots, coverage: cov)
      File.write(File.join(logdir, "codex.log"), "#{t.sub('codex.tool_result', 'codex.tool_outcome')}success=true arguments=#{JSON.generate(cmd1)} output=x\n")
      _, cov2 = IsolationAudit.codex_calls(logdir)
      check("isolation", "codex.log parsing: exact cmd and workdir (repo workdir read observed), ' output=' inside a command, spawn rejection; a renamed log event leaves coverage incomplete",
            parsed && observed.call(a) && !cov2["complete"], "parsed=#{parsed} read=#{read_status.call(a)} cov2=#{cov2.inspect[0, 120]}")

      # --- round-3 review: real Codex output headers; more git source spellings
      hdr = lambda do |code, body|
        "Chunk ID: bbbbbb\nWall time: 0.0000 seconds\nProcess exited with code #{code}\nOriginal token count: #{body.empty? ? 0 : 4}\nOutput:\n#{body}#{tail}"
      end
      logged = lambda do |cmd, code, body|
        dir = File.join(ws, "log-#{Digest::SHA256.hexdigest(cmd + code.to_s)[0, 8]}")
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "codex.log"),
                   "#{t}success=true output_truncated=false agent_name=/root arguments=#{JSON.generate('cmd' => cmd, 'workdir' => ws)} output=#{hdr.call(code, body)}")
        cs, cv = IsolationAudit.codex_calls(dir)
        IsolationAudit.audit(host: "codex", calls: cs, workspace: ws, policy: IMPL_POLICY, enforce: CODEX_WRITE,
                             protected_roots: fixture_roots, coverage: cv)
      end
      a = logged.call("cat ~/x 2>/dev/null", 1, "")
      b = logged.call("cat ~/x 2>/dev/null", 0, "")
      c = logged.call("cat ~/.codex/config.toml 2>/dev/null", 1, "model = \"x\"\n")
      d = logged.call("cat ~/nope.toml", 1, "cat: #{home}/nope.toml: No such file or directory")
      check("isolation", "real-format Codex entry (header and trailing record fields): exit 1 with empty output is unknown; exit 0 or output is observed; an error naming the path failed",
            read_status.call(a) == "unknown" && observed.call(b) && observed.call(c) && clean.call(d) && read_status.call(d) == "none",
            [a, b, c, d].map(&read_status).join(","))
      e1 = run.call("claude-code", [sh.call("cat /System/Volumes/Data#{home}/x 2>/dev/null", out: "(Bash completed with no output)", error: false)], CLAUDE_ENFORCED)
      e2 = run.call("claude-code", [sh.call("cat /System/Volumes/Data#{home}/x 2>/dev/null", out: "Exit code 1", error: true)], CLAUDE_ENFORCED)
      check("isolation", "Claude's empty-output placeholder and a bare 'Exit code N' count as no output (exit 0 still observed; exit 1 unknown)",
            observed.call(e1) && read_status.call(e2) == "unknown", [e1, e2].map(&read_status).join(","))
      gits = ["git clone file://$HOME/claude-skills /tmp/c && git -C /tmp/c log -p", "git clone file:///#{home.delete_prefix('/')}/claude-skills /tmp/c",
              "git archive --remote=~/claude-skills HEAD | tar -t", "git ls-remote ~/claude-skills", "git fetch-pack ~/claude-skills HEAD",
              "git -c remote.o.url=~/claude-skills fetch o", "git config remote.o.url ~/claude-skills; git fetch o",
              "git remote add o ~/claude-skills && git fetch o"]
      res = gits.map { |g| run.call("codex", [ex.call(g)], CODEX_WRITE) }
      check("isolation", "file:// URLs, archive --remote, ls-remote, fetch-pack and remotes set via -c, config or remote add are observed source reads",
            res.all?(&observed), gits.zip(res.map(&read_status)).reject { |_, s| s == "observed" }.inspect)
      a = run.call("codex", [ex.call("git fetch upstream")], CODEX_WRITE)
      check("isolation", "fetching a named remote whose url the run did not visibly set is unknown, not none", read_status.call(a) == "unknown", read_status.call(a))
      a = run.call("claude-code", [sh.call("cd / && ls -d */")], CLAUDE_ENFORCED)
      b = run.call("codex", [ex.call("cat /U*/*/claude-skills/evals/hidden/x")], CODEX_WRITE)
      check("isolation", "a single-segment glob at / lists top-level names (not a read of the home); a deeper glob still reaches it",
            clean.call(a) && read_status.call(a) == "none" && observed.call(b), [a, b].map(&read_status).join(","))

      # --- a Bash command the read-only guard hook
      # denied never ran, so its writes are prevented, not observed.
      mk = "mkdir -p /tmp/x-scratch/a && cd /tmp/x-scratch/a"
      ev = lambda do |result, err, marked = false|
        [{ "type" => "assistant", "message" => { "content" => [{ "type" => "tool_use", "id" => "t1", "name" => "Bash", "input" => { "command" => mk } }] } },
         { "type" => "user", "message" => { "content" => [{ "type" => "tool_result", "tool_use_id" => "t1", "is_error" => err, "content" => result }] } }
           .merge(marked ? { "tool_result_meta" => [{ "id" => "t1", "non_execution_kind" => "permission-rule" }] } : {})]
      end
      hook = "PreToolUse:Bash hook error: Read-only role (workflow): shell operator \"&\" is not allowed"
      denied = run.call("claude-code", IsolationAudit.claude_calls(ev.call(hook, true, true)), CLAUDE_ENFORCED, RO_POLICY)
      ran = run.call("claude-code", IsolationAudit.claude_calls(ev.call("", false)), CLAUDE_ENFORCED, RO_POLICY)
      quoted = run.call("claude-code", IsolationAudit.claude_calls(ev.call(hook, true)), CLAUDE_ENFORCED, RO_POLICY)
      check("isolation", "a Bash call the runtime marks as not executed (guard hook denial) is prevented; the same command that ran, or output that only imitates the denial text, is still an observed write",
            clean.call(denied) && !clean.call(ran) && !clean.call(quoted),
            [denied, ran, quoted].map { |x| x.dig("external_write", "status") }.join("/"))

    ensure
      FileUtils.remove_entry(ws) if ws && File.exist?(ws)
    end






    def accounting
      base = { "exit_status" => 0, "workspace_tree_ok" => true, "contamination" => { "suspect" => false }, "source_repo_unchanged" => true }
      ok = base.merge("observed" => { "model" => "claude-sonnet-5", "effort" => "medium" },
                      "accounting" => RoutingSupport.account(requested: { "model" => "claude-sonnet-5", "effort" => "medium" },
                                                             resolved: { "model" => "claude-sonnet-5", "effort" => "medium" },
                                                             observed: { "model" => "claude-sonnet-5", "effort" => "medium" }))
      fb_obs = { "model" => "claude-sonnet-5", "effort" => "medium" }
      fb = base.merge("observed" => fb_obs,
                      "accounting" => RoutingSupport.account(requested: { "model" => "claude-sonnet-5-5", "effort" => "medium" },
                                                             resolved: { "model" => "claude-sonnet-5-5", "effort" => "medium" },
                                                             observed: fb_obs))
      check("accounting", "matching run is valid model evidence", Evals.valid_for_model_evidence?(ok), "")
      check("accounting", "fallback run (requested 5.5, ran 5) is not valid evidence for the request",
            !Evals.valid_for_model_evidence?(fb) && fb["accounting"]["evidence_model"] == "claude-sonnet-5", fb["accounting"]["warnings"].first)
      recs = [ok.merge("task_id" => "t", "host" => "claude-code", "valid_for_model_evidence" => true, "deterministic_pass" => true,
                       "grader" => {}, "cost" => { "usd" => 0.1, "status" => "api_equivalent_estimate" }, "run_id" => "a"),
              fb.merge("task_id" => "t", "host" => "claude-code", "valid_for_model_evidence" => false, "deterministic_pass" => true,
                       "requested" => { "model" => "claude-sonnet-5-5" }, "grader" => {}, "run_id" => "b")]
      groups, excluded = Summary.group(recs)
      bad = { "exit_status" => nil, "source_repo_unchanged" => false, "host" => "codex", "tool_profile" => { "isolation_verified" => false } }
      reasons = Evals.invalid_reasons(ok.merge(bad))
      check("accounting", "one validity rule rejects a killed run, a changed source repo and unverified Codex isolation",
            reasons.any? { |r| r.start_with?("exit status") } && reasons.include?("source repo changed") && reasons.include?("codex isolation not verified"), reasons.join("; "))
      obs = ok.merge("isolation_audit" => { "external_read" => { "status" => "observed" }, "external_write" => { "status" => "none" },
                                             "reference_exposure" => { "status" => "none" } })
      unk = ok.merge("isolation_audit" => { "external_read" => { "status" => "unknown" }, "external_write" => { "status" => "unknown" },
                                             "reference_exposure" => { "status" => "none" } })
      check("accounting", "an observed external read invalidates; unknown reads and writes do not",
            Evals.invalid_reasons(obs) == ["external read observed"] && Evals.valid_for_model_evidence?(unk), Evals.invalid_reasons(obs).join("; "))
      check("accounting", "summary never credits a fallback run to the requested model",
            groups.none? { |g| g["model"] == "claude-sonnet-5-5" } && excluded.first["attributed_to"] == "claude-sonnet-5", excluded.first["reasons"].join("; "))
    end

    def tool_profile
      task = Evals.load_task("example-review")
      impl = Evals::Task.new("example-write", task.dir, task.data.merge("access" => "workspace-write", "role" => "wf-implementer"))
      Dir.mktmpdir do |a|
        _fm, body = Evals.claude_role("wf-reviewer")
        ro = Evals.claude_command(task, model: "m", effort: "low", artifacts: a, role_body: body)["argv"]
        rw = Evals.claude_command(impl, model: "m", effort: "medium", artifacts: a, role_body: body)["argv"]
        mcp = JSON.parse(File.read(File.join(a, "mcp-empty.json")))
        check("profile", "claude: --restricted, strict empty MCP config, no bypassPermissions",
              [ro, rw].all? { |v| v.include?("--restricted") && v.include?("--strict-mcp-config") && v.none? { |x| x.to_s.include?("bypass") } } && mcp == { "mcpServers" => {} }, "")
        check("profile", "claude read-only: only Read/Grep/Glob/Bash plus the Bash guard hook",
              ro[ro.index("--tools") + 1] == "Read,Grep,Glob,Bash" && ro.include?("--settings") && ro[ro.index("--settings") + 1].include?("readonly-bash-guard"), "")
        check("profile", "claude implementer: local file tools only, no MCP or network tools",
              rw[rw.index("--tools") + 1] == "Read,Grep,Glob,Bash,Edit,Write", "")
        cmd = Evals.claude_command(impl, model: "m", effort: "medium", artifacts: a, role_body: body, workspace: "/w")
        sb = cmd["settings"]["sandbox"]
        check("profile", "claude: Bash sandbox on, fail-closed, no unsandboxed retry, home unreadable; file tools denied under home; git ignores user config",
              sb["enabled"] && sb["failIfUnavailable"] && sb["allowUnsandboxedCommands"] == false && sb.dig("filesystem", "denyRead") == ["~"] &&
              cmd["settings"].dig("permissions", "deny").include?("Read(~/**)") && cmd["env"]["GIT_CONFIG_GLOBAL"] == "/dev/null" &&
              rw.include?("--settings"), "")
      end
      cx = Evals.codex_command(task, model: "m", effort: "low", ws: "/w", packet_file: "/p", out: "/o")["argv"]
      check("profile", "codex: codex-delegate with --eval (no user config, rules, hooks, agents, web search, image generation, goals)", cx.include?("--eval") && cx.first.end_with?("codex-delegate"), "")
    end
  end
end

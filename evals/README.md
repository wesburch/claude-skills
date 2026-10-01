# Eval harness

Local evaluation of **delegated** workflow roles (not the primary interactive
model) on tasks with known answers. It exists to produce trustworthy,
reproducible evidence before any change to which model fills a role.

This directory is the reusable framework. It ships one small example task.
Real tasks, their hidden answers and every model run belong in a private
**evidence store** outside this repository (see below).

```bash
evals/bin/verify                    # no-model proof of the harness; lists what it skipped
evals/test/test-evals               # deterministic tests
evals/bin/run --task ID --host claude-code|codex --model ID --effort low|medium|high [--trials N] [--dry-run]
evals/bin/summarize [--candidate MODEL@EFFORT --reference MODEL@EFFORT --task ID]
evals/bin/regrade [RUN_DIR ...]     # re-grade stored runs with current graders; no model call
ruby evals/analysis/compare.rb MANIFEST.json   # per-configuration analysis of one matrix
```

## Public-only and with an evidence store

| | Public-only checkout | With a store attached |
|---|---|---|
| Tasks found | `example-review` | the example plus every task in the store |
| Hidden data | `evals/hidden/example-review` (public on purpose) | the store's `hidden/` |
| Runs written to | `evals/results/` (gitignored) | the store's `results/` |
| `bin/verify` | example and generic checks; private checks listed as `SKIP` | also the store's task-specific checks |

Attach a store by setting `EVAL_STORE=/path/to/store`, or by putting
`store: /path/to/store` in `evals/config.local.yaml` (gitignored).
`EVAL_STORE=none` forces public-only mode. Nothing in this repository names
a store or depends on one.

A store is a directory, normally its own private git repository:

| Path | Content |
|---|---|
| `tasks/<id>/` | `task.yaml`, `packet.md`, optional `overlay/` |
| `hidden/<id>/` | reference answers, hidden tests, defect lists, rulings |
| `results/<date>/<run-id>/` | run records and artifacts |
| `analysis/` | matrix manifests and outputs, freeze files |
| `fixtures/verify_private.rb` | checks for those tasks, loaded by `bin/verify` |
| `config.local.yaml` | `repos:` paths of the source repositories on this machine |

Keep task definitions private even when their source is public: a published
packet or answer stops measuring anything.

## Tasks

A task directory holds `task.yaml` and `packet.md`: the only text the model
receives, recorded with every run. Reference data lives in `hidden/<task>/`
and is read only by graders after a run.

`task.yaml` fields: `id`, `category`, `role`, `access` (`read-only` or
`workspace-write`), `owned_files`, `packet`, `grader`, `eval_policy`, and the
source of the workspace:

- `repo` + `sha` + `scope`: an export of a source repository at a commit.
- `fixture`: a directory inside the task, for a self-contained task.
- `overlay`: files laid over the base as the uncommitted change under review.
- `overlay_sha` + `overlay_tree`: the same scope at a later commit, laid over
  the base as an uncommitted change, for reviewing a change taken from history.
- `workspace_tree`: the pinned tree of the base commit; checked every trial.
- `task_family`: tasks that count as one for the promotion minimum (a defect
  task and its control).
- `task_version`: declares the task frozen (see Freezing).

Graders:

| Grader | Task shape | Measures |
|---|---|---|
| `explore` | find the files or lines that satisfy a question | recall and precision against a reference set; cited paths exist and support the claim |
| `impl` | implement from a clear specification | hidden behavioural tests; changes outside the owned files |
| `review` | independent review of a change | seeded-defect recall, severity given, verdict, finding classes |

`example-review` is a review of a 40-line script with two planted defects. Its
reference is public, so it measures nothing; it exists to exercise the
harness and to show the format.

## Isolation and tool profile

- **Workspace**: a fresh export into a temp directory, committed once with a
  neutral author and the message `base`, so no history and no hint is
  visible. Its tree must equal the pinned `workspace_tree`.
- **Claude Code**: a fresh headless session per trial with
  `claude -p --restricted`: user, project and local settings are ignored; file
  tools are confined to the workspace; `--strict-mcp-config` with an empty MCP
  config; `--tools` limited to the role's local tools. Bash runs in Claude
  Code's OS sandbox: no network, writes only to the workspace and per-user
  temp, nothing under the home directory readable, no unsandboxed retry.
  Read-only roles add the fail-closed Bash guard with
  `READONLY_GUARD_ROOT=<workspace>`: every path a command names is resolved
  against the session's working directory, symlinks followed, and must land
  inside the workspace.
- **Codex**: `codex-delegate --eval`: a separate headless exec ignoring user
  config and execpolicy rules; hooks, agents, multi-agent, web search, image
  generation and goals disabled; standard service tier; role sandbox.
- **Three layers, none a substitute for another.** The guard refuses a
  command at dispatch. The OS sandbox contains what runs. The isolation audit
  reads the trace afterwards.
- **Isolation audit** (`lib/isolation_audit.rb`): decides from the trace
  whether the model gained information an isolated delegate should not have.
  It parses each tool call into read, write, exec and cwd events, resolves
  paths, classifies them by location (workspace, scratch, device, runtime,
  host, protected) and reports separately:
  - `external_read`, `external_write`: an access outside the allowed places
    that succeeded. Invalidates.
  - `reference_exposure`: a hidden reference line appears in model-visible
    tool output. Invalidates, whatever the path.
  - `cwd_escape`, `executed_outside`, `path_string_mentions`: recorded,
    never invalidating by themselves.
  - An access the trace cannot prove either way is `unknown`: recorded and
    counted, never invalidating.
  - A tool call the runtime marks as not executed (a guard denial) is
    `prevented`.

  The evals tree, this repository, the attached store and every configured
  source repository are protected locations.
- **Task isolation policy**: `eval_policy` in `task.yaml` (never shown to the
  model). `scratch_writes` allows test copies in temp areas;
  `cwd_independence` allows running from `/` or scratch.
- **Source repos** must be unchanged after a run.

## Run record

`results/<date>/<run-id>/record.json`, with `packet.md` and `artifacts/`
(trace, final reply, workspace diff). It records the suite and grading
versions, the task and its family, requested, resolved and observed model and
effort, service tier, tool profile, timing, tokens, cost, the grade, the
isolation audit, validity and `grade_history`.

A run is model evidence only when the observed model and effort match the
request, the run exited 0, there was no observed external read, write or
reference exposure, the workspace tree matches the pin, the source is
unchanged, and Codex isolation was verified. Other runs are kept and
attributed to the model that actually ran.

## Review finding classes

Each review finding gets exactly one class, tried in this order, using the
lists in the task's hidden `defects.yaml`:

| Class | Meaning | Counts as |
|---|---|---|
| `defect` | First finding credited to a seeded defect | Recall |
| `duplicate` | A tool-reported issue repeated, a second finding for a credited defect, or a listed restatement | Noise, not error |
| `valid_blocking` | A real defect other than the seeded one (`other_blocking`) | Justifies `CHANGES_REQUESTED`, even on a control |
| `incorrect` | A claim verified false against the reviewed revision | The only false positive |
| `process_note` | A statement about the review itself | Neither |
| `valid_out_of_scope` | True of the revision, not a seeded defect | Neither |
| `unclassified` | None of the above | Needs adjudication |

A run passes when it finds every critical seeded defect and its verdict is
the expected one, or is `CHANGES_REQUESTED` resting on a `valid_blocking`
finding it marked blocking, and no blocking finding of its own is verified
incorrect. A task with no seeded defects is a control.

Keyword rules are a first pass. A human reads the findings they credited and
the ones they left unclassified, against the code, and records each ruling in
`hidden/<task>/adjudications.yaml` (the finding's exact text, a class, a
reason, a date). Rulings are applied before the keyword rules, and
`bin/verify` checks that each is well formed.

## Cost

The metric is **cost per successful task**, computed from valid runs. Claude
cost is the CLI's list-price figure; Codex cost is registry list price times
tokens. Both are API-equivalent estimates, not subscription charges.

Each record's `cost_breakdown` keeps four parts apart: preparation (reusable
evaluation setup, apart from the packet a host writes per delegation),
delegate execution, host verification, and repair. A figure that was not
measured is labelled, never estimated.

## Promotion

`bin/summarize` prints a recommendation against the acceptance bar in
`config.yaml`. Clearing that per-task bar is a **preliminary** result. A
promotion can be recommended only when the candidate also has, for its own
model, effort and role, at least nine valid samples over at least three
meaningfully different tasks. Efforts are never pooled. Tasks that share a
`task_family` count once. It never edits the model registry; promotion is a
human decision.

## Freezing a task

A task that declares `task_version: N` may not run or be regraded unless
`analysis/<task_family>-freeze-vN.json` exists and every input it lists
(packet, task file, hidden list, grader) still has its recorded sha256.
`bin/verify` checks the same. Changing a frozen input means a new version
and a new freeze file. Pre-screen a control with a reviewer outside the
evaluated set before freezing it.

## Changing graders or hidden data

`bin/regrade` re-judges stored runs from their saved packet, reply, diff and
trace without calling a model, and appends the previous judgement to
`grade_history`. `suite_version` (what the model saw) never changes on
regrade. Derive reference data from the repository, not from a model's
answer. Change `packet.md` only by creating a new task or version.

## Adding a task

1. Pick work whose ground truth already exists: a known answer set, a commit
   with checkable behaviour, or a change with a defect that was later fixed.
2. Create `tasks/<id>/task.yaml` and `packet.md` in your evidence store,
   written as the delegate would have received it, with no reference data.
3. Put reference data in `hidden/<id>/`.
4. Run `bin/run --task <id> ... --dry-run` and pin the printed
   `workspace_tree`.
5. Add checks for it to the store's `fixtures/verify_private.rb`: the
   reference answer passes and broken answers fail. Then run `bin/verify`.

## Known limitations

- The Codex served tier is unverified; no billing multiplier is inferred.
- Codex has no read sandbox, so hidden-data protection there is
  detection-based; the reference-exposure check is the backstop.
- Temp areas are shared with the operator's own sessions.
- Hidden implementation tests run model-written scripts on the host in a
  temp copy with `HOME` redirected.
- Review grading matches free text by keywords plus a line window; that is
  why unclassified and credited findings are read by a human.
- The guard treats every argument as a possible path, so text that would
  resolve outside the workspace is denied too.
- The guard checks at most the first 1,000 matches of a glob, assumes the
  shell's default glob options, and does not see paths named inside list
  files or met while a command recurses. The OS sandbox is the layer for
  those.

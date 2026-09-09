---
name: engineering-workflow
description: Execute engineering tasks with proportionate verification, independent review, economical model routing, and bounded delegation. Use for implementation or /workflow, /workflow-quick, /workflow-standard, /workflow-full; adapt coordination to task risk and dependencies.
argument-hint: "[quick|standard|full|auto] [task description]"
metadata:
  short-description: Proportionate engineering workflow and evidence-based delegation
---

# Engineering workflow

Use the least expensive process that reliably meets the task's quality bar.
Profiles choose coordination and assurance; capability follows the assignment.
This skill does not authorize implementation for an advice-only request.

## Start and size

Read `.agents/engineering-workflow.md` at the relevant repo root if present.
Honor existing project commands, constraints, and the user's authorization.
Read [project-config.md](references/project-config.md) only to interpret an
override; absent a config, infer checks from the repo and use the defaults here.
Do not create configuration as a prerequisite.

Parse an initial `quick`, `standard`, `full`, or `auto` as the profile; the rest
is the task. Explicit profile wins over configured default; `auto` selects by
task shape. State the choice and reason in one sentence, then proceed.

| Profile | Default process |
|---|---|
| Quick | Current agent implements a bounded, low-risk change and runs appropriate checks; no reviewer or coordinator child |
| Standard | One implementer, appropriate verification, one independent reviewer; main session implements or coordinates |
| Full | Main session coordinates dependencies and scoped workers, integration checks, independent review; load [advanced.md](references/advanced.md) |

Choose quick for obvious, cohesive, low-risk work; standard for meaningful
feature or bug work; full for consequential architecture, dependent streams,
or long-running work that needs coordination. Fit the process to the task.
If quick reveals consequential or hard-to-detect risk, explain and add independent
review using standard's gates. Never downgrade merely to bypass a finding.
Full may simplify to standard as dependencies disappear, without restarting.

## Completion contract

- Establish outcome, constraints, ownership, and checks before implementing.
- Run appropriate checks on the final change. Record commands, results, and
  the artifact/revision checked; include relevant working-tree changes.
  Scripts supply deterministic evidence directly: no verifier agent is needed
  to read exit codes. Use visual judgment when behavior requires it.
- Standard/full review uses an instance that did not author the change. Supply
  requirements, final diff, and current verification evidence; see
  [delegation.md](references/delegation.md). If independent review is unavailable,
  finish useful implementation/checks and report review as outstanding; do not
  silently claim self-review satisfies the gate.
- Resolve verification failures before final review. An investigative review
  may help diagnose a failure, but does not count as completion approval.
- Repair defects and rerun checks affected by the change, including required
  project suites. Refresh review of affected areas; earlier approval cannot
  cover subsequent edits. Wider checks follow risk, not ritual repetition.
- Report what changed, actual checks, review outcome when applicable, and
  residual uncertainty. Passing tests alone does not prove requirements met.

No mandatory state log, task artifact, knowledge handoff, or human approval
ceremony. Project gates and authorization still govern merge/deploy/external
actions; a review verdict is not permission for them.

## Load only what changes the next decision

- Before delegating or choosing a different model: [routing.md](references/routing.md).
  That policy is also reusable for research and documentation assignments.
- Before dispatching: [delegation.md](references/delegation.md) and the relevant
  adapter in [runtime-adapter.md](references/runtime-adapter.md). No dispatch,
  no runtime discovery. Main session should fill a useful role.
- For concrete child model selection: [model-registry.md](references/model-registry.md).
- For repeated failures: routing's bounded recovery; do not repeat an unchanged approach.
- For a reusable decision or discovery at completion:
  [knowledge-handoff.md](references/knowledge-handoff.md). Routine changes skip it.

Do not load all references, spawn a role roster, or create tracking documents
just because the skill was invoked.

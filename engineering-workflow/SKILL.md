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

Before reading broadly, check cheaply for a usable, current local
code-intelligence index exposed by the project or agent environment. If present,
use it for initial orientation, symbol discovery, dependency tracing, and
blast-radius analysis. Treat indexed and inferred relationships as navigation
evidence, not source truth; inspect consequential source directly. A missing,
stale, or unsupported index must not block the task: use normal repository search.

Parse an initial `quick`, `standard`, `full`, or `auto` as the profile; the rest
is the task. Explicit profile wins over configured default; `auto` selects by
task shape. State the choice and reason in one sentence, then proceed.

| Profile | Default process |
|---|---|
| Quick | Current agent implements and checks a bounded, low-risk change; no mandatory reviewer, coordinator or task artifact |
| Standard | One implementer runs the checks; one independent reviewer assesses the final diff and evidence; no separate verifier |
| Full | Standard assurance plus the coordination, integration checks or specialist review justified by concrete dependencies/risks; load [advanced.md](references/advanced.md) |

Choose by consequences of error, not task name, tracking directory, line count
or duration. Documentation, copy and small visual adjustments are usually quick;
behavioral features and meaningful fixes are usually standard. Authentication,
authorization, data migrations, irreversible ledger changes and model promotion
need independent review and evidence for their specific failure modes; full is
appropriate when those risks require additional coordination or specialist work.
High risk alone does not require three agents or a separate test-running agent.
If quick reveals consequential or hard-to-detect risk, explain and add independent
review using standard's gates. Never downgrade merely to bypass a finding.
Full may simplify to standard as dependencies disappear, without restarting.

## Keep execution economical

- Work locally by default. Delegate only a bounded independent assignment or
  required review; the main session should not become a coordinator for a single
  implementer merely because the task has an ID.
- Read the assigned packet and relevant source once; use narrow searches and
  changed regions on follow-up. Load reference files only when their decision
  point is reached. Keep tool output to findings, failures and useful summaries.
- Run focused checks while iterating, then required integration/release checks
  once on the final applicable changeset. A later edit refreshes affected evidence;
  it does not automatically restart every check or every review from scratch.
- Keep long commands in the background when supported. Use completion notices or
  bounded waits; do not repeatedly poll unchanged state or ingest full logs.
- Preserve a compact handoff only when it prevents rediscovery. Use existing task
  records; no mandatory state machine, frozen ownership declaration or repeated
  evidence copying merely because a work package is tracked.

## Completion contract

- Establish outcome, constraints, ownership, and checks before implementing.
- Run appropriate checks on the final change. Record commands, results, and
  the artifact/revision checked; include relevant working-tree changes.
  Scripts supply deterministic evidence directly: no verifier agent is needed
  to read exit codes. The implementer may run and inspect both automated and
  visual checks; the independent reviewer spot-checks consequential evidence.
  Preserve real exit codes when filtering logs. Use visual judgment when needed.
- Standard/full review uses an instance that did not author the change. Supply
  requirements, final diff, and current verification evidence; see
  [delegation.md](references/delegation.md). If independent review is unavailable,
  finish useful implementation/checks and report review as outstanding; do not
  silently claim self-review satisfies the gate or mark review-gated work ready
  to merge. Add another reviewer only for a distinct unresolved risk.
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
Existing explicit project overrides remain binding unless the user authorizes
changing them. When simplifying a workflow, update its conflicting local rules
as well; changing the shared skill alone cannot remove a stronger repo override.

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

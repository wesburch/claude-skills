# Advanced coordination

Load for full-mode work. Add mechanisms only when they address an actual
dependency, recovery need, or unresolved risk. Full is not a required role roster.

## Parallel work

The main session owns decomposition, shared contracts, ready work, and integration.
Record owners and dependencies in the existing task tool or a compact task list.
Resolve shared interfaces before parallel implementation. Give workers disjoint
ownership or isolated branches; isolation still requires integration checks.
Do not parallelize competing edits to the same artifact.

Run stream checks, then check the integrated result at shared contracts, schemas,
and builds. Review the integrated diff with current evidence; separately approved
branches do not establish that their combination works.

Add a coordinator only when an independently managed stream has enough routing,
waiting, or recovery work to justify the extra context and messages. The main
session should not duplicate its bookkeeping. Respect runtime concurrency limits.

## Planning and specialist review

For consequential architecture or uncertain decomposition, use one independent
planning reviewer to assess both failure modes and implementation readiness.
Resolve material findings before dependent work starts. Planning/review does not
introduce a human approval gate beyond existing user authorization and project
rules. Ask for missing product decisions when they materially change the result.

Separate specialists or parallel plans only when distinct unresolved risks
justify their cost. State each additional pass's question and stop condition.
Do not repeat equivalent reviews after the evidence and question are unchanged.
Specialist blocking findings require repair and refreshed relevant verification
and review, just like ordinary findings.

## Durable tracking when useful

Use for multi-session recovery, concurrent coordination, or requested audit trails.
Prefer the project's existing tracker. Otherwise a task artifact under configured
`task_store` (default `docs/evidence/tasks`) can hold objective, ownership,
dependencies, latest revision, checks, findings, and next action.

A compact status such as ready / working / checking / reviewing / done / blocked
is sufficient unless the project already requires a richer state machine.
Record the blocker and resumption action. If an existing project uses the legacy
nine-state workflow, preserve its semantics and log requirements; these are no
longer universal defaults. No append-only transition ceremony for ordinary tasks.

Review approval refers to a specific artifact. New edits require refreshed
affected checks and review; no status label overrides that requirement.

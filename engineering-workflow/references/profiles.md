# Profiles

Three profiles. Same core primitives (roles, states, verification) at
different weight. Never invent a fourth profile; if none of these fit, use
`full` and trim what doesn't apply rather than build a bespoke shape.

## Recommending a profile

Recommend from task shape, not from how the user phrased the request:

| Signal | Push toward |
|---|---|
| One cohesive change, one file or a tight cluster, obvious correctness | quick |
| Low risk — no auth/data-model/security/state-management surface | quick |
| A feature with real scope, one repo, one implementer | standard |
| Independent work streams, a dependency graph, multiple repos | full |
| Architecture decisions, long-running or multi-day work | full |
| Meaningful parallelism actually available and worth coordinating | full |

State the recommendation in one line ("this looks like a `standard` — one
repo, one coherent feature, no cross-stream dependencies") and proceed on it.
A profile named by the user — via `$ARGUMENTS[0]` or in conversation — always
wins. `auto` in `$ARGUMENTS[0]` means "recommend regardless of any project
config default."

## QUICK

```
implementer → deterministic verification → completion / human review
```

- No coordinator, no independent reviewer. Adding either is the failure mode
  this profile exists to avoid — a one-line fix does not need a supervisor.
- The implementer runs verification itself (or triggers the project's
  deterministic commands) and reports PASS/FAIL directly.
- On FAIL: implementer repairs, re-verifies. No `FIXING` state — quick
  doesn't distinguish a verification bounce from a review bounce because
  there is no reviewer to distinguish it from.
- Completion is the implementer reporting done, with evidence, for the human
  (or a lightweight human-review gate the project config declares) to accept.
- Skip a knowledge handoff unless something genuinely significant fell out of
  a small change — see `project-knowledge`'s significance filter. Most quick
  tasks produce nothing worth a handoff.

## STANDARD (default)

```
task coordinator → implementer → deterministic verification
  → independent reviewer → repair if BLOCKING → deterministic verification (again)
  → review (again) → approved → merge per project rules
```

- One coordinator (`capable` tier), one implementer (`strong_implementer`),
  one verifier (`deterministic`, plus `visual_capable` if browser/visual
  judgment is acceptance-critical), one reviewer (`capable`).
- The coordinator reconciles task state, confirms the task is unblocked,
  assigns it, and routes the loop in `SKILL.md` — it does not implement or
  review.
- Full state machine applies: `references/state-machine.md`.
- Escalate to the user (standard has no root supervisor) on the triggers in
  `references/roles.md`.
- Produce a knowledge handoff at `APPROVED` — see
  `references/knowledge-handoff.md`.

## FULL

```
root/project supervisor → task/dependency graph → task coordinators
  → implementers → deterministic verification → integration verification
  → independent review → repair loops → escalation if needed
  → approval / merge per project rules
```

- Adds a root supervisor (`frontier` tier) above one-or-more standard loops
  running in parallel, one per task coordinator.
- The root supervisor's job is decomposition and the dependency graph, not
  running any individual task loop — that's each task coordinator's job,
  operating exactly as in `standard`.
- Non-overlapping file/ownership sets per implementer are mandatory before
  two tasks run concurrently. Two tasks whose ownership sets intersect do not
  run at the same time — file this in the task/dependency graph, not
  discovered mid-implementation.
- Add an integration-verification step after each stream's own deterministic
  verification, when streams touch a shared seam (a shared contract, a shared
  schema, a shared build). Integration verification is still deterministic
  wherever possible; it is not a second reviewer.
- Escalate to the root supervisor (not the user directly) on the triggers in
  `references/roles.md`; the root supervisor escalates to the user only for
  the higher-order items in that same file (destructive operations,
  cross-cutting product/architecture calls, credentials, external
  providers).
- One knowledge handoff per task at that task's `APPROVED`, not one handoff
  for the whole graph — `project-knowledge` reconciles across them later if
  it finds the same topic recurring.

## Downgrading mid-task

A `full` that turns out to be one implementer with no real parallelism can
drop to `standard` — say so and continue, don't restart. A `quick` that turns
out to need a real review (the diff touches auth, data model, or has a
BLOCKING-shaped risk the implementer notices) escalates to `standard` rather
than self-approving. Never silently downgrade `standard` to `quick` to skip
review.

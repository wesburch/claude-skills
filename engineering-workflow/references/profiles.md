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

### Optional: plan-review loop before implementation

For architecture-heavy or high-risk work, FULL may run a plan-review loop
before any implementer starts — not by default, only when the signals above
(architecture decisions, contested/high-stakes design, long-running work)
are strong enough to warrant it:

```
primary planner → independent architecture critic → primary planner revision
  → implementation-readiness reviewer → human approval
```

- **Primary planner** (`capable`) drafts the plan/decomposition.
- **Architecture critic** (`capable`, escalate to `frontier` when justified)
  is a separate instance from the planner — never the same agent reviewing
  its own plan. It looks specifically for: missing failure modes, unverified
  architectural assumptions, persistence/restart problems, race
  conditions/concurrency risks, duplicated state ownership, unclear
  component boundaries, missing test coverage, upstream/fork maintenance
  hazards, scope creep, and unresolved product/requirements ambiguity.
- The **primary planner** revises against the critic's findings.
- **Implementation-readiness reviewer** (`capable`, escalate to `frontier`
  when justified) asks exactly one question: *can independent
  implementation agents execute this plan phase-by-phase without inventing
  major architectural decisions?* If no, the plan returns to the primary
  planner for revision — this is a loop back to the critic step, not a
  one-shot gate.
- **Human approval** is the exit condition. Implementation does not start
  until a human has approved the plan this loop produced.

#### Optional: parallel independent planning

For especially difficult or high-risk architecture, the primary-planner step
above may itself fan out into two independent planners synthesized by a
third pass:

```
Planner A ─┐
           ├→ synthesis/review
Planner B ─┘
```

Do not make this the default — most FULL tasks get one planner. Reach for
parallel planning only when the architecture is contested or high-stakes
enough that two independently-reasoned drafts are worth the cost, the same
bar as reaching for the escalation reviewer.

### Optional: specialized review gates for high-risk phases

After a phase's deterministic verification and its normal independent
review, FULL may insert a specialized reviewer when that phase carries
unusual risk — concurrency/state-machine correctness, security/auth,
persistence/recovery, schema/data migrations, performance, distributed
systems, or destructive infrastructure changes:

```
implementer → deterministic verification → general reviewer
  → specialized reviewer (e.g. state-machine/concurrency)
  → repair if needed → deterministic verification (again)
  → relevant reviewers (again) → approved
```

- The specialized reviewer (`references/roles.md`) is a separate instance
  from the general reviewer, receives the same packet the Independent
  reviewer contract defines, and judges only its named risk area — it does
  not replace the general reviewer.
- Tier: `capable` by default, escalate to `frontier` when the specialized
  area itself turns out to be the hard, contested part of the review.
- A specialized BLOCKING finding routes to `FIXING` exactly like any other
  BLOCKING finding, and verification reruns exactly per
  `references/state-machine.md` — this does not add a new state.
- Use only when the phase's actual risk warrants it, not as a routine sweep
  on every phase of every full task.

**Governing principle for both mechanisms above:** every additional loop
must answer a different question or incorporate new evidence. Repeating
equivalent implementation/review passes without a distinct objective is
discouraged — do not add generic repeated "dev sweeps."

## Downgrading mid-task

A `full` that turns out to be one implementer with no real parallelism can
drop to `standard` — say so and continue, don't restart. A `quick` that turns
out to need a real review (the diff touches auth, data model, or has a
BLOCKING-shaped risk the implementer notices) escalates to `standard` rather
than self-approving. Never silently downgrade `standard` to `quick` to skip
review.

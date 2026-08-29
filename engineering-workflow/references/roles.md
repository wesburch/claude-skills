# Roles

Six roles, on capability tiers (see `model-routing.md` for what a tier
currently maps to). One agent instance holds one role for one task. What
makes a role independent is *which instance holds it*, not which provider
runs it — a Verifier and a Reviewer can be the same provider, but must be two
separate instances that neither wrote nor pass judgment on their own diff.

## Root / project supervisor — `frontier` — full only

**Responsibilities:** architecture, difficult decomposition, cross-repo
reasoning, dependency planning, ambiguous requirements, conflicting
evidence, difficult recovery, high-risk/system-level decisions, user
escalation.

**Escalate to the user when (default — see below):**
- a required input is missing (credentials, an external provider, a
  destructive data operation) that only the user can authorize
- a product or architecture choice would change the visible experience or
  an evidence/correctness claim
- a material scope expansion beyond what was asked
- credentials, signing, network services, or a new external provider come
  into play
- a destructive operation (deleting data, force-pushing, dropping a
  migration) is on the table

These are **defaults, not hardcoded policy** — a project's
`## Human gates` section in its config (`project-config.md`) can add,
remove, or replace any of them. Absent a project override, this is what a
root supervisor escalates on rather than deciding unilaterally.

**Do not** spend this role on routine bookkeeping, ordinary state transitions,
or anything a task coordinator can decide. If the root supervisor is
resolving "is this task ready" or "did the tests pass," that's a task
coordinator's job leaking upward.

## Task coordinator / per-task supervisor — `capable` — standard, full

**Responsibilities:** reconcile task state, identify ready/unblocked work,
assign ownership, dispatch implementers, route failed verification back to
implementation, route passed verification to review, maintain
transition/state logs, determine merge-readiness based on *existing* gates.

**Must not:**
- implement feature work
- waive or downgrade a failed check
- substitute its own judgment for the verifier's or reviewer's output
- make major architecture decisions without escalating

**Escalate to the root supervisor (full) or the user (standard) when
(default — see below):**
- requirements are ambiguous
- architecture is unclear
- dependencies conflict
- evidence conflicts
- repeated repair loops fail (a second bounce through `FIXING` for the same
  finding class is the signal, not a fixed count — use judgment, but don't
  let a third bounce pass without raising it)
- coordinator confidence is low

Like the root supervisor's list above, this is a default a project's
`## Human gates` config can add to, trim, or replace — not a fixed list
every project must escalate on identically.

## Implementer — `strong_implementer` — all profiles

**Responsibilities:** implementation, repairs, tests where appropriate,
responding to verification failures, responding to BLOCKING review findings.

Never downgrade implementer quality to save cost or time — this is the one
role the workflow treats as non-negotiable tier, in every profile.

## Verifier — `deterministic`, `visual_capable` for visual judgment — all profiles

Existing project scripts/tools remain authoritative for tests, lint,
typecheck, build, formatting, CI-equivalent commands, exit codes, evidence
binding, diff digests, and other objective checks. A model does not spend
tokens deciding whether a deterministic check passed — it runs the command
and reports the result verbatim.

For visual/browser judgment that a script genuinely cannot make (does this
look right, is this reachable, does this state actually render) — reach for
`visual_capable`. Visual verification is the Verifier's job, not a separate
QA role and not the Implementer's own screenshots (development notes, not
evidence).

## Independent reviewer — `capable` — standard, full

Receives, as one packet:
- the original requirements/spec
- acceptance criteria
- the final diff/artifact
- deterministic verification evidence (and visual evidence, if applicable)
- relevant design/reference material

Does **not** initially depend on the implementer's internal reasoning
transcript — it judges the packet, not the implementer's account of itself.

**Outputs:** `APPROVED` | `CHANGES_REQUESTED` | `ESCALATE`.

**Findings:** `BLOCKING` | `NON_BLOCKING` | `UNCERTAIN`. A finding names the
file, the observed behavior, and the source it violates (spec section,
acceptance criterion, contract) — "I would have done it differently" is not a
finding. `UNCERTAIN` does not block merge by itself but must resolve to
`BLOCKING` or `NON_BLOCKING` before `APPROVED` — by asking, not by assuming.

The reviewer never becomes the implementer. It may spot-check visually
itself if genuinely uncertain about a visual result, and reports what it saw
as a finding — it does not repair.

## Escalation reviewer — `frontier` (Opus acceptable alternate) — on escalation only

**Use when:** architecture is uncertain, security-sensitive behavior exists,
state/concurrency behavior is difficult, evidence conflicts, repeated repair
cycles fail, requirements remain unclear, reviewer confidence is low,
reviewers disagree, or tests pass but behavior still looks suspicious.

Model-family diversity may be used intentionally here — a different provider
than the implementer/reviewer used, specifically for a second, independently-
reasoned opinion on a hard case. This is the one place in the workflow where
that's worth the cost.

## Optional FULL-only roles

These three exist only for FULL's optional plan-review loop and specialized
review gates (`references/profiles.md`) — not used in quick or standard, and
not mandatory even in full. Reach for them only when a phase's actual
difficulty or risk warrants it; see `profiles.md`'s governing principle
before adding one.

### Architecture critic — `capable`, escalate to `frontier` when justified — optional, full only

A separate instance from the primary planner — never the planner reviewing
its own plan. Looks specifically for: missing failure modes, unverified
architectural assumptions, persistence/restart problems, race
conditions/concurrency risks, duplicated state ownership, unclear component
boundaries, missing test coverage, upstream/fork maintenance hazards, scope
creep, and unresolved product/requirements ambiguity. Produces findings for
the planner to revise against — it does not rewrite the plan itself.

### Implementation-readiness reviewer — `capable`, escalate to `frontier` when justified — optional, full only

Answers exactly one question: *can independent implementation agents execute
this plan phase-by-phase without inventing major architectural decisions?*
A "no" returns the plan to the primary planner for revision. Does not
evaluate architecture quality itself — that's the architecture critic's job;
this role only checks whether the (already-critiqued) plan is concrete
enough to hand to implementers.

### Specialized phase reviewer — `capable`, escalate to `frontier` when justified — optional, full only

A separate instance from the general independent reviewer, engaged after
normal review for a phase with unusual risk in one specific area:
concurrency/state-machine correctness, security/auth, persistence/recovery,
schema/data migrations, performance, distributed systems, or destructive
infrastructure changes. Receives the same packet the Independent reviewer
contract defines and judges only its named risk area — it supplements the
general reviewer's verdict, it does not replace it. A specialized BLOCKING
finding follows the same `FIXING` → re-verification path as any other
BLOCKING finding.

## Cross-cutting separation rules

- The reviewer may never be the implementer of the diff under review. Reuse
  across rounds is preferred for continuity; a fresh reviewer is always
  acceptable.
- The verifier and reviewer are distinct instances — never one agent wearing
  both hats.
- The verifier is never the implementer of the diff it verifies, and never
  its reviewer.
- The coordinator/supervisor never implements fixes, waives a failed check,
  or substitutes its own reading of the code for verifier or reviewer output.

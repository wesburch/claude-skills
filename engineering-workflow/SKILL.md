---
name: engineering-workflow
description: Run a portable multi-agent software-engineering workflow with task-size profiles (quick/standard/full), role boundaries, capability-tier model routing, verification-before-review, repair loops, and escalation. Use when starting implementation work, sizing a task, coordinating implementer/verifier/reviewer roles, or when the user runs /workflow, /workflow-quick, /workflow-standard, /workflow-full, or asks to route work through "the workflow" or "the review loop".
argument-hint: "[quick|standard|full|auto] [task description]"
metadata:
  short-description: Portable multi-agent engineering workflow with profiles, roles, and repair loops
---

# Engineering Workflow

A portable execution workflow: task-size **profile** → **role** assignment on a
**capability tier** → deterministic verification → independent review → repair
→ re-verification → approval, ending in a compact **knowledge handoff**.

This Skill owns *execution*. It does not reconcile knowledge — see
[project-knowledge](../project-knowledge/SKILL.md) for that, and
`references/knowledge-handoff.md` for the contract between the two.

It does not own a runtime. Herdr is today's runtime adapter; the workflow's
semantics must survive moving off it. See `references/runtime-adapter.md`.

## Always first

1. Look for a project config file — see `references/project-config.md` for the
   exact path, field contract, and safe defaults when one doesn't exist. Load
   it before picking a profile or dispatching a role; it can override the
   default profile, commands, gates, and knowledge mode.
2. Do not assume Herdr. Resolve the runtime adapter per
   `references/runtime-adapter.md` (project config → environment → ask).

## Pick a profile

| Profile | Use for | Load |
|---|---|---|
| **quick** | Tiny, cohesive, low-risk changes; little/no parallelism | `references/profiles.md` |
| **standard** | Meaningful feature work (the default) | `references/profiles.md` |
| **full** | Multi-repo, multi-stream, dependency graphs, architecture decisions, long-running work | `references/profiles.md` |

Recommend a profile from task shape (size, blast radius, number of
independent streams, presence of architecture/cross-repo concerns), state the
recommendation and why in one line, and proceed on it — but a profile the
user names (via `$ARGUMENTS[0]` or in conversation) always wins over the
recommendation. Load `references/profiles.md` in full before executing any
profile; do not improvise the flow from this table alone.

## Roles

Small, explicit role set on **capability tiers**, not model names — the
mapping from tier to a specific model lives in one place so it can change
without touching workflow logic. Load `references/roles.md` for full
responsibilities, boundaries, and escalation triggers; load
`references/model-routing.md` for the tier-to-model mapping and
reasoning-effort guidance.

| Role | Tier | Used in |
|---|---|---|
| Root/project supervisor | `frontier` | full only |
| Task coordinator | `capable` | standard, full |
| Implementer | `strong_implementer` | all |
| Verifier | `deterministic` (+ `visual_capable` for browser/visual judgment) | all |
| Independent reviewer | `capable` | standard, full |
| Escalation reviewer | `frontier` | standard/full, on escalation only |
| Architecture critic, implementation-readiness reviewer, specialized phase reviewer | `capable`, escalate to `frontier` when justified | full only, optional |

Quick skips coordinator and reviewer entirely — see `references/profiles.md`.

FULL has two further optional mechanisms it may reach for on genuinely
difficult or high-risk work: a plan-review loop before implementation starts,
and specialized review gates for high-risk phases. Neither is a default for
every full task — see `references/profiles.md` for the loops themselves and
`references/roles.md` for the roles they use. The governing principle for
both: **every additional loop must answer a different question or
incorporate new evidence — repeating equivalent implementation/review passes
without a distinct objective is discouraged.**

## The core loop

This loop is the spine of standard and full, and is not skippable once a
profile uses it:

```
implementer → deterministic verification → independent reviewer
   ↑                     |  FAIL                      |
   |                     ↓                             |
   └──────────── IMPLEMENTING            BLOCKING → FIXING → back to verification
                                          no BLOCKING → APPROVED → merge per project rules
```

Hard rules, no exceptions:

- **Verification never runs stale.** A reviewer is never engaged before this
  round's evidence has run and passed.
- **A failed verification is not a review finding.** It returns to
  `IMPLEMENTING`, not `FIXING`. `FIXING` exists only for reviewer BLOCKING
  findings.
- **The original implementer repairs its own work.** The reviewer judges; it
  does not become the implementer.
- **Verification always reruns after a repair.** There is no `FIXING` →
  `REVIEW` edge. Full state list and legal transitions:
  `references/state-machine.md`.
- **The coordinator/supervisor never waives a failed check, substitutes its
  own judgment for the verifier's or reviewer's, or implements fixes itself.**
  It routes state and decides merge-readiness on the evidence it was handed.

## Verification

Deterministic wherever the project has a script or command for it — tests,
lint, typecheck, build, formatting, CI-equivalent commands, exit codes. A
model does not spend tokens deciding whether a deterministic check passed;
the project's own commands (from `references/project-config.md`) are
authoritative. Reserve a `visual_capable` model for genuine visual/browser
judgment a script cannot make (does this look right, is this control
reachable) — not for reading exit codes.

## Escalation

The coordinator escalates to the root supervisor (full) or asks the user
directly (standard/quick, no root supervisor present) when: requirements are
ambiguous, architecture is unclear, dependencies or evidence conflict,
repeated repair loops fail, or confidence is low. See `references/roles.md`
for the full trigger list and `references/model-routing.md` for when to
reach for `frontier`-tier escalation review specifically (architecture
uncertainty, security-sensitive behavior, concurrency, disagreement between
reviewers, tests passing but behavior still suspicious). Do not default to
frontier reasoning for ordinary routing, summaries, or state bookkeeping.

## Knowledge handoff

At meaningful task completion (normally at `APPROVED`), produce a small
structured handoff — not a reconciled knowledge write. See
`references/knowledge-handoff.md` for the exact fields and where they're
recorded. Then this workflow's job on that task is done:

- **Knowledge reconciliation runs off the critical path.** Dispatch it to
  `project-knowledge` (fire-and-forget via the runtime adapter, or leave it
  for the user to run later) rather than doing it inline.
- **A knowledge failure does not block merge or the next task**, unless the
  project config explicitly sets a knowledge gate for this milestone.
- Do not perform significance filtering, deduplication, or wiki decisions
  here — that is `project-knowledge`'s job entirely.

## Arguments

- `$ARGUMENTS[0]` — profile override: `quick` | `standard` | `full` | `auto`
  (or omit to auto-recommend). `auto` forces the recommendation even if a
  project config sets a different default.
- `$ARGUMENTS[1:]` — the task description, or a pointer to a spec.

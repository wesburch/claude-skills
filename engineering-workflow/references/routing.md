# Routing

Use this policy for engineering, research, documentation, or investigation.
It chooses assignments; the invoking workflow supplies its completion gates.

## Choose the work before the model

1. Use an existing command for mechanical work and objective checks.
2. Stay in the current session when its context makes completion cheaper than
   preparing a handoff, waiting, and inspecting the result.
3. Delegate a substantial bounded assignment, an independent review, or a
   parallel investigation that contributes evidence the host actually needs.
   Do not duplicate the delegate's work while waiting. Keep the immediate
   blocker local when delegation would only make the host idle, unless the
   delegate's capability, context isolation, or review independence warrants it.
4. Select capability from ambiguity, blast radius, context needs, and how
   reliably success can be checked. Task size and profile do not set the tier.

| Band | Starting use |
|---|---|
| Small/fast | Extraction, inventory, repetitive transformations, fixtures with explicit checks |
| Balanced | Bounded coding, investigation, ordinary independent review |
| Strong | Ambiguous debugging, architecture, consequential state changes, difficult review |

Use stronger judgment when errors are consequential or hard to detect, even
for a tiny change. A large repetitive assignment may still fit a smaller model.
Choose review capability from the risk of missed defects, not the author's tier.
Cross-provider review offers another perspective, not guaranteed correctness.

Consult [model-registry.md](model-registry.md) when selecting a child model;
consult [runtime-adapter.md](runtime-adapter.md) only when dispatching. Honor
explicit user model/provider choices. Never imply a child changes the host model.
Set model and effort explicitly where supported; avoid inheriting expensive
reasoning for bookkeeping. Give one sentence of rationale, not a model catalog.

## Bounded recovery

Each delegate receives an attempt/time budget and stop conditions. Default to
one initial attempt and one repair of the same failure class, then return the
evidence for reassessment. This is a limit on unproductive repetition, not a
requirement to consume both attempts or stop after unrelated successful fixes.

| Failure | Next action |
|---|---|
| Clear implementation defect | Repair, then rerun affected checks |
| Same failure after a reasonable repair | Reassess the hypothesis; escalate diagnosis or replace implementer |
| Flaky check or environmental failure | Establish the cause; resolve prerequisites without pretending checks passed |
| Missing access, permission, or user decision | Report the concrete blocker; ask only for the missing input |
| Assignment needs broader scope | Return to host for decomposition or reassignment within authorization |
| Reviewer disagreement | Inspect disputed evidence; seek a second opinion if unresolved |

The host may make one stronger reassignment for a repeated reasoning failure
within authorized scope. If that also fails, report the blocker and useful
evidence rather than initiating an unbounded escalation chain. Project/user
budgets override these defaults. Do not upscale models to fix missing access.
Preserve failed approaches and evidence when replacing an implementer.

## Measure results, not dispatch counts

Optimize cost per accepted result at the required quality, considering host
and child context, reasoning, cached/uncached usage when exposed, retries,
verification, and latency. Lower token count and lower price are different.
API pricing does not establish subscription allowance consumption.

During an agreed pilot, compare representative tasks against the old process:
total available usage/cost, elapsed time, repairs, dispatches, review defects,
and human corrections. Label unavailable data. Do not run paid model comparisons
just to select a route or promise savings from an unmeasured preference.

## Design sources

Adapted principles, not installed dependencies:
- [claudex-route](https://github.com/chaseai-yt/claudex-loop/blob/main/skills/claudex-route/SKILL.md): stay local, role first, scoped cross-provider handoffs.
- [efficient-frontier](https://github.com/BuilderIO/skills/blob/main/skills/efficient-frontier/SKILL.md): compact evidence returns, ownership, stop conditions.

Use this local policy without fetching these sources on each task.

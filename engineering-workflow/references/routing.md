# Routing

Stable routing policy for engineering, research, documentation, or
investigation. It names capability classes and effort tiers, never models.
Concrete models live in [../registry/models.yaml](../registry/models.yaml) and
are chosen by the [resolver](resolver.md):

```
task shape -> capability class (+ modifiers) -> effort tier -> resolver -> model -> quality gates
```

The invoking workflow supplies completion gates; this file supplies who does
the work and at what depth.

## Choose the work before the model

1. Use an existing command for mechanical work and objective checks.
2. Stay in the current session when its context makes completion cheaper than
   preparing a handoff, waiting, and inspecting the result. A tiny interactive
   edit stays with the host.
3. Delegate a substantial bounded assignment, an independent review, or a
   parallel investigation that contributes evidence the host needs. While it
   runs, do other useful work instead of duplicating it. Keep the immediate
   blocker local unless delegation adds capability, context isolation, or
   review independence.
4. Pick the class from the task shape below: ambiguity, blast radius, context
   needs, and how reliably success can be checked. Task size and profile do not
   set the class.

## Capability classes

| Class | Meaning |
|---|---|
| `deterministic` | No model: tests, types, lint, build, schema and contract checks, browser assertions, the registry check |
| `efficient-bounded` | Cheap, fast, tool-competent; success is externally checkable |
| `capable-delegated` | Solid coding and judgment from a clear packet |
| `primary-interactive` | The user's session model. Chosen by the user for judgment, autonomy, ambiguity handling and low rework; never auto-selected or downgraded to save cost |
| `frontier-judgment` | Highest judgment, used sparingly for consequential or disputed calls |

Modifiers: `visual` (needs browser/computer use and screenshot reading) and
`cross-family` (a different provider than the author; see below).

## Task shapes

| Task shape | Class | Effort tier | Gate | Escalate when |
|---|---|---|---|---|
| Fuzzy product or design problem | primary-interactive, with the user | session | User confirms decisions | n/a: decisions belong to the user |
| Architecture planning | primary-interactive | session | Challenge if hard to reverse | Owner-owned decision appears |
| Architecture challenge | frontier-judgment, cross-family when available | deep | Findings resolved | Findings disputed |
| Well-specified implementation | host when context is warm; otherwise capable-delegated | standard; deep if intricate | Checks + independent review | Same failure survives one repair |
| Tiny mechanical edit | host (interactive); efficient-bounded (batch/headless) | light | The proving check | Diff escapes the bounded area |
| Broad repo exploration | efficient-bounded | light | Host spot-checks cited paths | Citations fail spot-checks |
| Primary-source research | capable-delegated | standard | Citations resolve and support claims | Sources conflict |
| Debugging with a reproduction | host or capable-delegated | standard | Red -> green, regression test | Repro fixed, symptom remains |
| Debugging without a reproduction | primary-interactive or frontier-judgment | deep | Loop built before any fix | No loop after a bounded attempt |
| Independent code review | capable-delegated | standard | Verdict with evidence | Consequential risk named below |
| Spec-compliance review | capable-delegated | standard; deep if consequential | Findings cite the original requirement | Requirement source disputed |
| Coding-standards review | deterministic first, then capable-delegated for judgment calls | light | Tool-enforced issues excluded | Repeated mechanical finding: propose a check |
| Subagent coordination | host; no separate coordinator | session | n/a | n/a |
| Deterministic verification | deterministic | none | Real exit codes | Flaky: find the cause |
| Visual or browser verification | assertions first, then capable-delegated + `visual` | standard | Named bands; failures named | Assertion cannot express it |
| Long-running migration | capable-delegated per slice; host integrates | standard or deep; extended only per Effort | Per-slice + integration checks | Slice fails twice |

Review escalates to `frontier-judgment` (role `wf-reviewer-deep`) for
authorization/security, data or ledger integrity, migrations, irreversible
architecture, high blast radius, or a disputed finding.

## Effort

Model and effort are separate decisions. Tiers are `light`, `standard`, `deep`
and `extended`; the registry maps each tier to a model-specific level because
vendors recalibrate levels between generations.

- `deep` is the automatic ceiling for serious work.
- `extended` (xhigh-class) needs a one-line escalation record naming one trigger:
  the same task failed at `deep` and the failure analysis shows reasoning depth
  was the bottleneck; a single autonomous run expected to exceed about 30
  minutes, with a token budget; or an irreversible decision where local evals
  showed extended beat deep on comparable work.
- `max` is selected only on an explicit user request or local-eval evidence for
  that task class. Modes that spawn uncontrolled parallel agents (Codex `ultra`)
  are outside automatic routing.
- Fast/priority service tiers belong to the user's session. Delegates run on the
  standard tier unless the user asks otherwise.

Before raising effort, rule out non-reasoning causes: missing context, vague
requirements, missing access, poor testability, wrong decomposition, missing
documentation, or unavailable runtime evidence. Fix those instead.

## Escalation order

1. Improve context, packet, or specification.
2. Raise effort up to `deep`.
3. Raise the capability class (one stronger reassignment).
4. Add cross-family review when it adds independent evidence.
5. `extended`, with an escalation record.
6. `max`, only by explicit user request or strong local-eval evidence.

Honor explicit user and project model/provider choices at every step. A child
never changes the host model. Give one sentence of rationale, not a catalog.

## Cross-family modifier

Consider it for consequential architecture, security-sensitive changes,
disputed findings, high-blast-radius migrations, or where another model family
adds genuinely independent evidence; ordinary reviews stay single-family.
Dispatch only through the read-only headless adapter in
[runtime-adapter.md](runtime-adapter.md), and only when the project allows it
(`cross_family_review` in [project-config.md](project-config.md)). When the
project restricts it, report cross-family review as recommended and leave it to
the user to start. Cross-family review offers another perspective, not
guaranteed correctness.

## Bounded recovery

Each delegate receives an attempt/time budget and stop conditions. Default to
one initial attempt and one repair of the same failure class, then return the
evidence for reassessment. This limits unproductive repetition; it does not
require consuming both attempts.

| Failure | Next action |
|---|---|
| Clear implementation defect | Repair, then rerun affected checks |
| Same failure after a reasonable repair | Reassess the hypothesis; escalate diagnosis or replace implementer |
| Flaky check or environmental failure | Establish the cause; resolve prerequisites without claiming checks passed |
| Missing access, permission, or user decision | Report the concrete blocker; ask only for the missing input |
| Assignment needs broader scope | Return to host for decomposition or reassignment within authorization |
| Reviewer disagreement | Inspect disputed evidence; seek a second opinion if unresolved |

The host may make one stronger reassignment for a repeated reasoning failure
within authorized scope. If that also fails, report the blocker and evidence
rather than starting an unbounded escalation chain. Project/user budgets
override these defaults. Missing access is fixed by access, not a larger model.
Preserve failed approaches and evidence when replacing an implementer.

## Measure results, not dispatch counts

Optimize cost per accepted result at the required quality: host and child
context, reasoning, cached/uncached usage when exposed, retries, verification,
latency, and human attention. Lower token count and lower price are different.
API pricing does not establish subscription allowance consumption.

Ordinary task execution runs no paid model comparisons. Model evaluation is a
separate, explicitly budgeted activity whose results enter the registry as
`LOCAL_EVAL` evidence and may promote a candidate; the policy above stays unchanged.

## Design sources

Adapted principles, not installed dependencies:
- [claudex-route](https://github.com/chaseai-yt/claudex-loop/blob/main/skills/claudex-route/SKILL.md): stay local, role first, scoped cross-provider handoffs.
- [efficient-frontier](https://github.com/BuilderIO/skills/blob/main/skills/efficient-frontier/SKILL.md): compact evidence returns, ownership, stop conditions.

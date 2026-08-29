# Model routing

The workflow reasons in **capability tiers** everywhere else in this Skill.
This file is the only place a concrete model name appears — that's
deliberate, so the mapping can change without touching profiles, roles, or
the state machine.

## Tiers

| Tier | What it's for |
|---|---|
| `frontier` | Architecture, difficult decomposition, cross-repo reasoning, conflicting evidence, difficult escalation, high-risk recovery. |
| `capable` | Coordination, independent review, mechanical-but-judgment-requiring work. |
| `strong_implementer` | Implementation and repair. Never downgraded regardless of profile. |
| `deterministic` | Running the project's own tests/lint/typecheck/build/CI-equivalent commands and reporting results verbatim. Prefer a script over a model call entirely wherever the project has one. |
| `visual_capable` | Browser/visual judgment a script can't make. |

## Current preferred mapping

| Tier | Current preferred implementation |
|---|---|
| `frontier` | Codex GPT-5.6 Sol, high reasoning when justified |
| `capable` | Claude Sonnet |
| `strong_implementer` | Claude Opus |
| `deterministic` | Project's own scripts/commands (not a model call) |
| `visual_capable` | Claude Sonnet |

Escalation reviewer specifically: Codex Sol High preferred, Claude Opus
acceptable alternate — model-family diversity from whatever
implemented/reviewed the task is worth the cost for a genuinely hard case.

This table is the thing to edit when a new model ships or a preference
changes. Nothing else in this Skill should need to change with it.

## Reasoning-effort guidance

Use **high** reasoning for:
- architecture
- difficult decomposition
- conflicting evidence
- difficult escalation
- high-risk recovery

Do **not** default to high effort for:
- ordinary routing
- summaries
- worker completion bookkeeping
- straightforward state transitions

A task coordinator resolving "is this task unblocked" or "did the checks
pass" does not need frontier reasoning at high effort — that's exactly the
routine bookkeeping the tier split exists to keep off the expensive tier.

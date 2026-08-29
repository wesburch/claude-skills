Run a task through the `engineering-workflow` Skill — quick/standard/full
profiles, role-based implementer/verifier/reviewer loop, capability-tier
model routing, verification-before-review, repair loops, escalation, and a
knowledge handoff at completion.

## Steps

1. Read `~/.claude/skills/engineering-workflow/SKILL.md` in full.
2. Parse the argument below: if the first token is `quick`, `standard`,
   `full`, or `auto`, it's a profile override; the rest (or all of it, if no
   such token) is the task description.
3. Follow SKILL.md's "Always first" step to load project config
   (`references/project-config.md`) and resolve the runtime
   (`references/runtime-adapter.md`), then run the profile's flow from
   `references/profiles.md`, dispatching roles per `references/roles.md`
   and `references/model-routing.md`, tracking state per
   `references/state-machine.md`, and producing a knowledge handoff per
   `references/knowledge-handoff.md` at completion.

## Output

Report the profile used (recommended, and why, or the override given), the
roles dispatched, the final state, and whether a knowledge handoff was
produced.

$ARGUMENTS

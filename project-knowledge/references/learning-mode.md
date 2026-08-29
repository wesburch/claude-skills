# Learning mode

For personal projects, learning-oriented knowledge is the default
(`knowledge_mode: learning`) — the goal is to deeply learn the apps being
built, not just to keep a decision log. This mode adds richer,
teaching-ready source material to entries that already cleared the
significance filter. It does not lower the bar for what gets promoted, and
it does not generate the teaching material itself.

## What this produces vs. what it doesn't

**Produces:** enough high-quality source material in the entry itself that a
future teaching pass could generate architecture courses, guided code tours,
prerequisite maps, quizzes, feature-rebuild exercises, progressive coding
exercises, "build this subsystem yourself" challenges, debugging exercises,
architectural-tradeoff exercises, or rebuild-from-scratch guidance.

**Does not produce:** any of those things themselves. Do not generate a full
course, quiz, or exercise set after a task — capture the seeds; generate the
artifact later, as its own separate, explicitly-requested pass.

## Fields

Add these to an entry only when `knowledge_mode: learning` and the entry
already cleared `significance.md` — not on every entry, and not in
`minimal`/`decisions` mode at all:

| Field | Captures |
|---|---|
| Concepts | The underlying ideas this entry actually teaches, named plainly. |
| Prerequisites | What a learner needs to already understand first. |
| Why this matters | The motivating problem, not just the mechanism. |
| Common mistakes | What's easy to get wrong here, especially anything this task itself got wrong first. |
| Relevant code | Pointers to the actual implementation, not a restatement of it. |
| Small exercise idea | A short, concrete "try changing X and see" seed. |
| Quiz idea | One or two questions this entry's content could support. |
| Rebuild challenge idea | What "build this subsystem yourself" would look like for this specific piece, if it's substantial enough to warrant one. |

Skip whichever fields don't genuinely apply — a small, self-contained LESSON
doesn't need a rebuild-challenge seed; forcing one produces filler, not
material.

## Scope discipline

Do not produce these fields for trivial work — they only attach to entries
that already earned a place in the knowledge base. A task that produces no
durable knowledge under `significance.md` produces no learning-mode material
either, even in `learning` mode.

# Knowledge handoff

`engineering-workflow` produces raw material. It never reconciles,
deduplicates, or writes durable knowledge itself — that's
[project-knowledge](../../project-knowledge/SKILL.md)'s entire job. This
file defines the contract between the two: what gets handed off, when, and
where it's recorded.

## Why this split exists

The implementer/coordinator producing this handoff should not spend time
searching the existing knowledge base, deduplicating against it, or writing
polished documentation — that's a different kind of work, done by a
different (and cheaper) pass, and doing it inline would slow builders down
for no benefit to the task at hand. See `project-knowledge`'s own
`reconciliation.md` for what happens to this material next.

## When

At meaningful task completion — normally when a task reaches `APPROVED`
(`state-machine.md`). Not at every verification pass, not at every repair
round. A `quick` task usually produces nothing here at all; most small
changes have no candidate worth recording (see `project-knowledge`'s
`significance.md` for the filter that ultimately decides this — the
implementer's job here is just to flag candidates, not to pre-judge them).

## Where

One more append-only section in the same task artifact used for evidence and
review (`state-machine.md`), not a separate file or mechanism. Written once,
at completion.

## Fields

Don't force this exact schema where a project already has a cleaner
convention — but absent one, this is the default shape:

| Field | What goes here |
|---|---|
| `task` | Task ID / pointer to the task artifact. |
| `project` | Which project/repo this is. |
| `profile` | Which profile ran (`quick`/`standard`/`full`). |
| `significance_hint` | The implementer's own guess at whether this is worth durable knowledge — `none` / `maybe` / `likely` — and one line why. Not a decision; `project-knowledge` decides. |
| `candidate_decisions` | Anything intentionally chosen during this task, with the alternatives considered if known. |
| `candidate_lessons` | Anything a future task would otherwise have to rediscover. |
| `architecture_impacts` | What this task changed about how the system is shaped, if anything. |
| `unexpected_findings` | Anything surprising that came up, whether or not it was the point of the task. |
| `future_implications` | What this task sets up, constrains, or blocks for later work. |
| `relevant_files` | Files a reconciliation pass would need to look at. |
| `evidence_references` | Pointers into the task artifact's own evidence/review sections — not copies of them. |

Leave a field empty rather than pad it. A handoff with five empty fields and
one real `candidate_lessons` entry is doing its job; a handoff where every
field got filled in because the schema asked for it is noise for the next
pass to wade through.

## What this is not

- Not a decision to write durable knowledge — `significance_hint` is a
  hint, not a verdict.
- Not a place to repeat the full task history — that lives in the task
  artifact's own evidence/transition sections; this handoff points at it,
  it doesn't duplicate it.
- Not a blocking step. Producing the handoff is part of reaching
  `APPROVED`; reconciling it is not, unless the project config explicitly
  sets a knowledge gate for this milestone.

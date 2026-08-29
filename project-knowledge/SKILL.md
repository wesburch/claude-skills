---
name: project-knowledge
description: Maintain a deduplicated, provenance-aware project knowledge base from engineering-workflow's task handoffs — classify each candidate as NEW/EXTEND/UPDATE/CONFLICT/DUPLICATE against existing knowledge, preserve decision history and supersession, never invent rationale, and decide what (if anything) graduates to the personal wiki. Use when reconciling a knowledge handoff, auditing project knowledge for drift, answering a question from project knowledge, or when the user runs /knowledge, asks to "reconcile knowledge", "what do we know about X in this project", or "should this go in the wiki".
argument-hint: "[reconcile|audit|query] [handoff pointer or question]"
metadata:
  short-description: Deduplicated, provenance-aware project knowledge base with wiki handoff
---

# Project Knowledge

Turns raw handoffs from [engineering-workflow](../engineering-workflow/SKILL.md)
into a small, deduplicated, provenance-aware knowledge base — and decides
what (if anything) is worth sending to the personal
[wiki](../wiki/SKILL.md). This Skill never appends "lessons learned" after
every task; it reconciles against what's already known first.

This is a separate concern from execution on purpose: builders should not be
slowed down by heavy documentation work, so reconciliation runs off the
critical path, normally after `engineering-workflow` has already reached
`APPROVED`.

## Always first

1. Read the project config at `.agents/engineering-workflow.md` (same
   provider-neutral file `engineering-workflow` reads — one config, not two)
   for `knowledge_mode`,
   `knowledge_store`, and `decisions_store`. Defaults if absent or unset:
   `knowledge_mode: learning` for a personal project (`decisions` otherwise —
   ask if genuinely unclear which this is), `knowledge_store: docs/knowledge`.
2. Check for an existing decision-record convention before assuming one
   doesn't exist — look for `decisions_store`, or a conventional
   `docs/decisions/`, `docs/adr/`, or equivalent. **Prefer and extend an
   existing convention over creating a parallel one.** If the project already
   has ADRs with their own template, `DECISION`-type entries go there, in
   that template — see `references/provenance.md`.
3. Retrieve only *relevant* existing knowledge for the task at hand — not the
   whole knowledge base. See `references/reconciliation.md` for what
   "relevant" means and a worked example.

## Task history vs. project knowledge — keep these distinct

- **Task history** — what happened in *this* task: evidence, decisions made
  during execution, state transitions, review findings. Owned by
  `engineering-workflow`'s task artifact. Can repeat context for provenance.
- **Project knowledge** — what we currently understand about the system:
  architecture, constraints, decisions, tradeoffs, reusable lessons, future
  implications. Owned here. Avoids repetition — one canonical entry per
  topic, not one per task that touched it.

Never write task-history material into the knowledge base as if it were
canonical understanding, and never let the knowledge base balloon into a
second copy of the task log.

## Pick the operation

| The user wants | Load and follow |
|---|---|
| Reconcile a task's knowledge handoff into durable knowledge | `references/reconciliation.md` |
| A health check of the knowledge base (drift, broken supersession chains, orphaned entries) | `references/reconciliation.md` (Audit section) |
| An answer synthesized from existing project knowledge | `references/reconciliation.md` (Query section) |

Load the matching section in full before acting — don't work from this page
alone.

## Significance filter

Not every task produces durable knowledge. Load `references/significance.md`
before writing anything — it's the gate that keeps this from becoming
append-only noise. The short version: would a future engineer plausibly ask
"why is it like this," or have to rediscover this if it weren't recorded? If
no, this task's handoff likely produces nothing here.

## Knowledge types

Nine distinct epistemic types — FACT, DECISION, RATIONALE, TRADEOFF, LESSON,
OPEN_QUESTION, ASSUMPTION, CONSTRAINT, EXTENSION_POINT. Don't blur them.
`references/knowledge-types.md` defines each, and carries the hard rule on
never inventing rationale that was never established.

## Provenance and supersession

Durable knowledge traces to its source — task ID, commit, files, evidence,
date — never invented. A later decision that replaces an earlier one is
recorded as a supersession, not a silent rewrite; old decisions stay
readable as history. `references/provenance.md`.

## Learning mode

For personal projects (`knowledge_mode: learning`), capture enough source
material — concepts, prerequisites, why it matters, common mistakes,
exercise/quiz/rebuild-challenge seeds — that a future teaching pass can build
courses, tours, and exercises from it later, without generating any of that
now. `references/learning-mode.md`. Only for entries that already cleared
the significance filter — learning mode enriches what's promoted, it doesn't
lower the bar for promotion.

## Personal wiki handoff

This Skill decides *what* is worth sending to the personal wiki; the `wiki`
Skill decides *how* to ingest it. It never knows or needs to know the wiki's
physical path or sync mechanism. `references/wiki-handoff.md`.

## Hard rules

- Retrieve relevant existing knowledge before writing anything new — never
  append blind.
- Classify every candidate as NEW / EXTEND / UPDATE / CONFLICT / DUPLICATE
  before writing. A DUPLICATE gets no new entry.
- Never invent a rationale the original work didn't establish — record the
  gap instead.
- Never silently overwrite a superseded decision — preserve it as history.
- A knowledge failure here does not block a builder or the next engineering
  task, unless the project explicitly requires knowledge capture before a
  milestone.
- Don't dump repetitive task summaries into the personal wiki — only
  durable, generalizable material clears that bar.

# Personal wiki handoff

`/wiki` refers to the existing personal Obsidian wiki workflow, operated
entirely by the `wiki` Skill (`~/Documents/MyProjects/wiki/`, ingested via
its `references/ingest.md`). `project-knowledge` never touches that wiki's
files directly, never knows its physical path beyond what the `wiki` Skill
already documents, and never re-implements ingestion, indexing, or linting —
all of that already exists and works; using it again here would be exactly
the duplicate mechanism this whole design is trying to avoid.

The division of labor is exact:

- **`project-knowledge` decides WHAT** is worth sending to the personal wiki.
- **`wiki` decides HOW** to ingest it — saving the source, writing/updating
  pages, updating `index.md`, cross-linking, logging.

## Deciding what crosses over

For each entry that reached `NEW`, `EXTEND`, or `UPDATE` in
`reconciliation.md`, decide: project-only, personal-wiki, both, or neither.

Favor sending to the personal wiki:
- durable architecture understanding that generalizes past this one project
- generalizable engineering concepts and mental models
- cross-project patterns
- important debugging lessons (the kind worth remembering the *next* time a
  similar symptom shows up somewhere else)
- rationale/tradeoff lessons with reusable shape, not just this project's
  specific numbers
- material genuinely useful as source for future courses/exercises
  (learning-mode entries are natural wiki candidates for this reason)

Keep project-only:
- anything that only makes sense with this project's specific architecture,
  data model, or constraints as context
- `DECISION`/`FACT`/`CONSTRAINT` entries that are true here and nowhere else
- routine task-scoped material that cleared the significance filter but
  isn't generalizable

**Do not dump repetitive task summaries into the personal wiki.** A wiki
candidate should read as something worth knowing independent of which task
produced it.

## Handing it off

`project-knowledge` prepares the content — a synthesized, self-contained
write-up of the entry, with its provenance (task/commit/project) carried
along as a citation, not as wiki-internal metadata. It then hands that
content to the `wiki` Skill's ingest operation as **inline text**: the
`ingest.md` reference already accepts a file path, a URL, or pasted/inline
text as its source, and inline text is exactly this case — no wiki-specific
file format or schema needs to exist on the `project-knowledge` side for
this to work.

Concretely: invoke the `wiki` Skill and follow `references/ingest.md`,
supplying the synthesized write-up as the source content in place of a file
path or URL. Let `wiki` decide where it lands, what it links to, and how the
index updates — that's its contract to keep, not this Skill's to second-guess.

## What this Skill must never do

- Assume or hardcode the wiki's on-disk location.
- Write directly into the wiki's `pages/`, `index.md`, or `log.md`.
- Re-derive the wiki's naming, frontmatter, or linking conventions —
  `wiki`'s own `SCHEMA.md` is authoritative there, and this Skill doesn't
  need to know it.
- Send something to the wiki just because it was promoted here — promotion
  to the project knowledge base and promotion to the personal wiki are two
  separate decisions, and most entries only clear the first one.

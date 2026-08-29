# Reconciliation

The core operation: take a task's knowledge handoff (or a batch of them),
compare each candidate against what's already known, and write only what's
actually new or changed.

## Storage layout

Default, when `knowledge_store` isn't set and no equivalent convention
already exists — reuses the same index+pages+log shape the `wiki` Skill
already proves out, scoped to this project instead of the personal wiki:

```
<knowledge_store>/            (default: docs/knowledge)
  index.md                    catalog of every entry, grouped by type/topic
  entries/                    one file per canonical topic
  log.md                      append-only reconciliation log
```

Each entry file carries frontmatter — `title`, `type` (one of
`knowledge-types.md`'s nine), `status` (`current` | `superseded`), `created`,
`updated`, and provenance (`references/provenance.md`) — followed by the
content itself.

**Exception — decisions.** If the project already has an ADR-style
convention (`decisions_store`, or a conventional `docs/decisions/`,
`docs/adr/`), `DECISION`-type canonical entries go there instead, in that
convention's own template, not in `<knowledge_store>/entries/`. Don't create
a second decisions mechanism next to one that already works. Every other
type still lives in `<knowledge_store>/`.

## Retrieval — relevant, not exhaustive

Never load the whole knowledge base for one task. Retrieve what the task's
own subject matter touches, the way you'd scope a search, not a dump.

**Worked example.** Task: "draft nomination timer." Retrieve:
- draft engine architecture
- timer ownership decisions
- websocket synchronization
- prior timer lessons
- relevant state-management knowledge

Then reconcile the new candidates against *those* topics — not against
every entry the project has ever accumulated.

## Classification

Compare each candidate from the handoff (or from direct investigation, for
`audit`) against the retrieved existing knowledge, and classify it:

| Class | Meaning | Action |
|---|---|---|
| `NEW` | Genuinely absent from current knowledge. | Create a new canonical entry. |
| `EXTEND` | The concept already exists; this task adds real nuance or evidence. | Enrich the existing entry — don't fork a second one. |
| `UPDATE` | Existing knowledge was correct but the system has since changed. | Update current knowledge, preserving the superseded version as history (`provenance.md`). |
| `CONFLICT` | New evidence contradicts current knowledge. | Do not silently overwrite. Flag it, preserve both readings, and note the uncertainty explicitly until it's reconciled. |
| `DUPLICATE` | Already adequately captured. | No new entry. Optionally strengthen provenance on the existing one if this task adds a corroborating source. |

Prefer improving one canonical topic over creating several task-specific
versions of the same learning — a `NEW` classification should be the
exception on an active project, not the default outcome.

## Reconcile — step by step

1. Read the handoff (`engineering-workflow`'s
   `knowledge-handoff.md` fields), or gather the candidates directly for an
   `audit`/manual reconcile.
2. Retrieve relevant existing entries per the retrieval rule above.
3. Run the significance filter (`significance.md`) on each candidate before
   spending time classifying it.
4. Classify each surviving candidate (table above).
5. Write only what the classification calls for — apply
   `knowledge-types.md`'s type discipline and `provenance.md`'s citation and
   supersession rules as you write.
6. Update `index.md` for anything created or materially changed.
7. Append one line per candidate to `log.md` — what was decided and why,
   even for `DUPLICATE`/no-op outcomes, so a later reconciliation pass
   doesn't redo the same comparison from scratch.
8. Decide the wiki question per `wiki-handoff.md` for anything that reached
   `NEW`, `EXTEND`, or `UPDATE`.

A reconciliation pass that touches nothing (every candidate is `DUPLICATE`
or failed the significance filter) is a valid, common outcome — say so
plainly rather than manufacturing an entry to justify the pass.

## Audit

A lighter, standalone health check — not tied to a specific handoff. Check
for:

- entries in `entries/` missing from `index.md`, or vice versa
- broken supersession chains (`SUPERSEDES` pointing at something that no
  longer exists, or a `current` entry that something else already
  supersedes)
- entries with no provenance
- near-duplicate topics that should have been merged
- `DECISION`-type entries that drifted outside `decisions_store` when one
  exists
- stale `ASSUMPTION` or `OPEN_QUESTION` entries that later work has since
  resolved but never closed out

Report only — don't auto-merge or auto-fix. Let the user pick what to
resolve, the same way `wiki`'s own lint operation does.

## Query

Answer a question from existing project knowledge: retrieve relevant
entries (same relevance-scoped retrieval as reconciliation), read them, and
answer with citations to the specific entries consulted. Note gaps or
contradictions in the knowledge base explicitly rather than papering over
them. This does not write anything unless the answer surfaces material
worth promoting — in which case, fall back to the reconcile steps above for
that material.

# Provenance and supersession

## Provenance

Durable knowledge is traceable to its source when practical. Useful
provenance includes, as available:

- task ID
- commit
- relevant files
- decision record (a link to the ADR, if this project has one)
- evidence artifact
- date
- reviewer result
- source document

**Never invent provenance.** If a field isn't known, omit it — don't fill it
with a plausible-looking placeholder. A candidate arriving with no
provenance at all is still worth recording if it clears the significance
filter; it's just recorded as unsourced, not backfilled with an invented
source.

## Deferring to an existing decision convention

If the project already has an ADR-style store (`decisions_store`, or a
conventional `docs/decisions/`, `docs/adr/`), write `DECISION`-type entries
there, in that project's own template — don't invent a second one. A
template seen in practice, worth reusing as-is when a project's ADRs
resemble it:

```markdown
# NNNN — <short title>

- **Date:** <date>
- **Status:** proposed | accepted | superseded
- **Approved by:** <who, or "pending review">
- **Affects:** <areas/components>

## Context
<what prompted this decision>

## Decision
<what was chosen>

## Consequences
<what follows from it>
```

When no such convention exists, a `DECISION`-type entry in
`<knowledge_store>/entries/` follows the same shape — Context / Decision /
Consequences — since it's a good, proven shape and there's no reason to
invent a different one for entries that happen to live in a different
directory.

## Supersession

Never erase architectural evolution. When a later decision replaces an
earlier one, the *new* entry (or ADR) records both directions:

```markdown
**CURRENT:** <new approach>

**SUPERSEDES:** <old approach, or a link to the old entry/ADR>

**Changed:** <date / task / commit>

**Reason:** <the known rationale for the change — or "not established" per
knowledge-types.md if it genuinely isn't>
```

The *old* entry is preserved, marked `status: superseded` in its
frontmatter, with a pointer forward:

```markdown
**Superseded by:** <link to the new entry/ADR>, <date>
```

Do not rewrite the old entry as if the earlier decision never existed —
future readers benefit from seeing that the system evolved and why, not just
where it landed. This is exactly what `UPDATE` in `reconciliation.md`'s
classification means in practice: update current knowledge while preserving
the historical record, never overwrite it in place.

## CONFLICT is not supersession

A `CONFLICT` classification (new evidence contradicts current knowledge,
without a clear "this replaces that" story yet) is not the same as
supersession. Don't resolve a CONFLICT by unilaterally picking a side and
writing it as if it were settled — flag it, preserve both readings, and
leave it for a human or a later task to resolve. Promoting a CONFLICT to a
supersession requires an actual reason the earlier reading was wrong or
outdated, not just that the new evidence is more recent.

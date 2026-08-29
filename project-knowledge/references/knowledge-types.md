# Knowledge types

Nine distinct epistemic types. Every canonical entry declares exactly one in
its frontmatter `type` field. Don't blur them — a FACT dressed up as a
DECISION reads as more settled than it is, and a LESSON dressed up as a
CONSTRAINT reads as more binding than it is.

| Type | Is | Is not |
|---|---|---|
| `FACT` | Current observable behavior or state. | A claim about why it's that way (that's RATIONALE). |
| `DECISION` | What was intentionally chosen. | Why it was chosen (RATIONALE) or what it cost (TRADEOFF) — those are separate, even when they live in the same entry. |
| `RATIONALE` | Why a decision was made. | Present when it wasn't actually established — see below. |
| `TRADEOFF` | What was gained and what was given up. | A justification for the choice — that's RATIONALE; a TRADEOFF can exist even when the RATIONALE is unknown. |
| `LESSON` | A reusable engineering insight. | A restatement of what the code already makes obvious. |
| `OPEN_QUESTION` | Unresolved uncertainty, named explicitly. | A rhetorical question — it should be answerable, and someone should eventually own answering it. |
| `ASSUMPTION` | Currently believed but not fully established. | A FACT — the distinction is exactly whether it's been verified. |
| `CONSTRAINT` | A rule or limitation future work must respect. | A preference — a CONSTRAINT should say what breaks if violated. |
| `EXTENSION_POINT` | An intended future evolution path. | A speculative idea nobody has committed to — that's closer to an OPEN_QUESTION or not worth recording at all. |

## No invented rationale

This is the rule most worth enforcing under time pressure, because it's the
one an agent is most tempted to skip to make an entry look complete.

**Do not infer a confident rationale after the fact if the original work
didn't establish one.** If something was chosen but the reason isn't
documented anywhere the reconciliation can point to, write it as:

```markdown
**Decision:** X was chosen.

**Recorded rationale:** not established.

**Knowledge gap:** the reason should be clarified if it becomes important —
<what would make it important, if known>.
```

Do not fabricate a plausible-sounding "why" just to make the entry read as
finished. A DECISION with an honest "not established" rationale is more
useful than one with an invented rationale that later turns out wrong and
gets trusted anyway.

## RATIONALE, TRADEOFF, and DECISION can — and often should — live together

A single canonical entry frequently carries a DECISION with its RATIONALE
and TRADEOFF as sections underneath it, the way an ADR does. The type
discipline is about not blurring what's *established* from what's
*inferred* within that entry, not about forcing one type per file.

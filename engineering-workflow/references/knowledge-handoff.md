# Optional knowledge handoff

Capture a concrete reusable decision, discovery, or lesson at meaningful
completion. Routine tasks produce no handoff unless the project requires one.
Do not search the knowledge base or load another skill just to decide whether
there is an obvious candidate; final significance/deduplication belongs to
[project-knowledge](../../project-knowledge/SKILL.md).

Preserve its existing field contract; omit empty fields:

| Field | Content |
|---|---|
| `task`, `project`, `profile` | Task reference, repo, profile used |
| `significance_hint` | none / maybe / likely, with brief reason; not a reconciliation decision |
| `candidate_decisions` | Actual decisions and known alternatives/rationale |
| `candidate_lessons` | Reusable findings backed by evidence |
| `architecture_impacts`, `unexpected_findings`, `future_implications` | Only concrete relevant observations |
| `relevant_files`, `evidence_references` | Source pointers, not repeated transcripts |

Append to an existing task artifact when present. Otherwise use a compact section
in the completion report, or persist under configured `task_store` when a durable
handoff is needed. No full task log is required just to retain one useful lesson.
Do not invent rationale or force every field to be populated.

Reconciliation stays outside the implementation path. Leave the packet for later
or dispatch project-knowledge when that action is within scope and supported by
the runtime. Do not start an untracked background process. A reconciliation
failure does not block completion unless an explicit project milestone gate says
otherwise. Engineering-workflow does not write reconciled wiki/knowledge entries.

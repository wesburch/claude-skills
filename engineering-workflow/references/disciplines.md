# Specialist disciplines

Load only for a selected discipline. Selection lives in [SKILL.md](../SKILL.md).
The source and exact selected paths live in [skills.lock](../../third-party/skills.lock).
Read the selected `SKILL.md` through `~/.claude/skills/<name>/SKILL.md` or
`~/.codex/skills/<name>/SKILL.md`; both resolve to the same pinned checkout.
Load only supporting references needed for the current decision. If unavailable,
report the missing installation and use the workflow's existing process; do not
fetch an unpinned replacement.

## Precedence and ownership

User/project constraints and workflow safety, completion gates and these
adaptations govern composed skill instructions. The workflow owns delegation
([delegation.md](delegation.md)), independent review, and context lifecycle
([context-lifecycle.md](context-lifecycle.md)). Disciplines never dispatch agents
or introduce their own orchestrator, review, ticketing or handoff process.
The host assigns research through existing routing; delegates return user-facing
questions to the host. Research discoverable facts; keep genuinely user-owned
decisions with the user. In headless work, return the unresolved decision
frontier and stop dependent work rather than inventing the user's answer.

Select one discipline for the phase's actual blocker. Without an explicit
request, resolve acceptance decisions first, contested vocabulary next, and
interface design after prerequisites settle. An ambiguous product decision does
not automatically require domain-modeling. Reassess only when the phase or its
blocker changes; replace the selection rather than stacking disciplines.
Explicit requests for several disciplines are sequenced across relevant phases.

## grilling

Use when acceptance depends on multiple unresolved user-owned decisions. One
question can be asked inline without loading this discipline. Ask only the
currently answerable decision frontier, with recommendations; research factual
prerequisites through the host. Stop when the frontier is empty or the user asks
to use recommendations. Existing authorization is sufficient to proceed; do not
add an upstream reconfirmation gate. The durable result is only the confirmed
choices needed by this task, recorded with their existing owner. Recommendations
accepted by the user count as decisions; unanswered decisions do not.

## domain-modeling

Use for new, overloaded or contested domain concepts and invariants. Merely
reading established vocabulary does not select this discipline. If `GLOSSARY.md`
exists, use its terms. Create it only when resolved domain vocabulary needs a
durable home; keep it limited to domain terms and their meanings/relationships,
not implementation details, task state or architectural vocabulary. ADRs use
the project's existing ADR/decisions location and are warranted only when all
three hold: hard to reverse, surprising without context, and a real tradeoff.

## codebase-design

Use narrowly when module responsibility, interface design or seam placement is
the central problem. Apply the interface/testability reasoning to that problem;
finish when responsibility, caller contract and proving checks are clear. Keep
established project/domain language; the upstream engineering glossary is not a
reason to rename domain concepts or populate `GLOSSARY.md`. Reuse an existing
architecture decision instead of running a duplicate architecture pass.
Design-it-twice is available only for FULL work on hard-to-reverse interfaces,
and only when explicitly requested. The host owns any resulting delegation.

## diagnosing-bugs

Scale to the failure rather than importing every upstream phase:

- QUICK: reproduce → fix → green; add a regression test when cheap. An obvious
  bug needs no specialist by default or ranked-hypothesis ceremony.
- STANDARD: build a red-capable loop for the actual symptom, localize the cause,
  fix it, preserve regression coverage at a useful seam, and remove temporary
  instrumentation.
- FULL/incident: use the full hypothesis discipline where uncertainty warrants
  it, with falsifiable predictions and probes that distinguish causes.

If a bounded attempt cannot establish a usable loop, return evidence and the
missing access/input through the host. Workflow recovery budgets still apply.

## tdd

An implementation method, not another verification gate: choose a meaningful
behavioral seam, run a useful test red, implement the smallest vertical slice,
then run it green. Choose seams within the task's existing authorization; ask
only for unresolved user-owned decisions, not routine test placement. An upstream
cross-skill reference does not automatically compose another discipline, and
upstream review instructions defer to our independent review. Repeat for the next required behavior; final verification
and independent review stay with the workflow. Skip default TDD for docs,
configuration, generated or mechanical work already adequately pinned by
checks. Honor explicit TDD requests where a meaningful behavioral test exists;
explain when there is no such seam rather than manufacturing a no-op test.

## Borrowed mechanisms

These are adaptations, not additional installed runtime disciplines:

- **research:** use primary sources for consequential external facts; record
  sources and uncertainty where the decision lives. Unknown facts are research
  assignments, not questions for the user.
- **to-tickets / implement-spec:** vertical tracer slices, independently
  checkable outcomes, blocked-by edges, and a ready dependency frontier;
  expand → migrate → contract for wide refactors. Apply the small decomposition
  rules in [advanced.md](advanced.md) only when dependencies warrant them.
- **retro:** address recurring friction at the cheapest durable level: a navigation
  pointer for repeated search, a deterministic check for mechanical mistakes,
  reviewer guidance for judgment calls, and improved tooling/information access
  for environment friction. Prune stale or no-op instructions before adding more. A retrospective or new artifact is not mandatory.
- **handoff:** suggest a discipline when it helps the next objective, inside the
  existing minimal handoff; lifecycle decisions and storage stay unchanged.
- **writing-for-agents:** progressive disclosure, pointers instead of duplicated
  context, explicit completion criteria, one source of truth, repository and
  environment as source of truth, positive steering, and pruning stale/no-op
  instructions. Keep this skill out of runtime composition and installation.

`implement`, `implement-spec`, and `code-review` are not composed or installed
workflow disciplines; `/workflow` remains the orchestrator and review contract.

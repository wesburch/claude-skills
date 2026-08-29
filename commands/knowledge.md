Run the `project-knowledge` Skill — reconcile a task's knowledge handoff
against existing project knowledge, audit the knowledge base for drift, or
answer a question from it.

## Steps

1. Read `~/.claude/skills/project-knowledge/SKILL.md` in full.
2. Parse the argument below: if the first token is `reconcile`, `audit`, or
   `query`, it selects the operation (default `reconcile`, against the most
   recently completed task's handoff if none is otherwise pointed to); the
   rest is the handoff pointer or question.
3. Follow SKILL.md's "Always first" step to load project config and check
   for an existing decision-record convention, then follow the matching
   operation in `references/reconciliation.md` — applying
   `references/significance.md` before writing anything, and
   `references/knowledge-types.md` / `references/provenance.md` /
   `references/learning-mode.md` as you write.

## Output

For `reconcile`: what was classified (NEW/EXTEND/UPDATE/CONFLICT/DUPLICATE)
and why, per candidate. For `audit`: the health-check findings, report only.
For `query`: the answer with sources consulted. In every case, note whether
anything was sent to the personal wiki (`references/wiki-handoff.md`) and
why or why not.

$ARGUMENTS

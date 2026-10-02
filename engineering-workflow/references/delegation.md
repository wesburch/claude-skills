# Delegation and review

One agent may implement locally or coordinate workers. Do not spawn a duplicate
coordinator. Implementation authors cannot independently review their own diff;
the host may review a worker's change if the host did not author it. A reviewer
inspects evidence and code read-only; when a check needs rerunning, the host runs
it. Neither requires another agent.
If the host edits the diff, assign independent review elsewhere.

## Handoff packet

Give a fresh agent only the context needed to execute:

- Repo/cwd, objective, requirements, acceptance criteria.
- Assignment type: implementation, investigation, or independent review.
- Owned files or bounded search area; exclusions and relevant references.
- Baseline and relevant committed, staged, unstaged, and untracked changes.
- Permitted actions, tools, the `wf-*` role with its resolved model/effort
  ([resolver.md](resolver.md)), and a task-specific time budget.
- Applicable project rules, including `.agents/engineering-workflow.md` and
  any code-index-first requirement. For a tool-enabled child, name the relevant
  instruction files to read; for a tools-disabled reviewer, supply the relevant
  rules in the packet. Do not assume the runtime inherits host instructions,
  hooks or CLAUDE.md context; confirm its behavior and pass missing constraints
  explicitly. Use the index before code discovery when required, and ordinary
  text search for prose or literal strings that do not require code discovery.
- Cost limits: start with summaries, failure excerpts or log tails, expanding
  only to diagnose missing context. Preserve full logs and actual exit status.
  Prefer completion notifications; otherwise use bounded waits/status checks
  with backoff, not a tight polling loop. Return a compact report.
- Verification commands or behavior to check; prior failures and hypotheses.
- Selected discipline path, if any, and its applicable workflow adaptations
  from [disciplines.md](disciplines.md); load only that discipline.
- If `GLOSSARY.md` exists, use its terms. Questions for the user return to the
  host; discoverable facts remain research work.
- Expected compact return and stop conditions.

Do not attach the full parent transcript. Reviewers receive requirements and
evidence, never a session handoff or the implementer's reasoning narrative. Workers
do not recursively delegate: `wf-*` roles have no delegation tool, and fan-out
stays with the host.
Give independent workers non-conflicting ownership; pause host edits to their
files. Reuse a worker for repairs when productive; replace it when evidence
shows continuity is no longer helping.

Stop and return evidence when assumptions are materially false, ownership or
permissions need expansion, the budget is reached, the same failure survives
a reasonable repair, or a claim cannot be supported. Scope questions go to the
host, which resolves routine choices within the user's existing authorization.

Return findings/result, changed files, checks and outcomes, evidence pointers,
residual risks, and any stop condition or decision needed. Keep logs in artifacts
when large; return the relevant excerpt and location, not the full transcript.
An explorer whose findings later agents will reuse writes them to a file those
agents can read, rather than leaving the host to restate them.

## Independent review

One reviewer covers ordinary work: dispatch `wf-reviewer`, or `wf-reviewer-deep`
when [routing.md](routing.md) escalates the review. Add a specialist only for a
distinct unresolved risk, not for a generic second sweep.

The review packet adds to the handoff packet:

- **Original requirement source**: the user's request, requirements, acceptance
  criteria or spec as originally stated, by path or verbatim. When a narrowed
  child packet or implementation contract also exists, include it as context and
  keep the original as the source of truth.
- **Reviewed revision**: commit, or base plus working-tree diff, and the final diff.
- **Deterministic evidence**: checks run on that revision with commands and results,
  and the tools that already enforce standards (lint, types, format, schema, build,
  contract checks).
- **Standards sources**: pointers to repository standards and conventions.
- **The contract below**, verbatim.

Review contract:

> Review the final change on two axes and return both sections.
>
> **SPEC**: Does the change do what the original requirement asks, completely and
> without unrequested behavior? Cite the requirement (ID, heading or quote) for
> each finding. Judge against the original source even where a narrower contract
> exists.
>
> **STANDARDS**: correctness, meaningful test coverage (tests that could fail),
> regression and security risk, architectural fit, maintainability, and repository
> conventions. Skip anything a listed tool already enforces. When the same
> mechanical issue recurs, recommend a deterministic check instead of repeating it.
>
> For each finding give location, observed behavior, the violated requirement or
> standard, evidence or reproduction, and severity: blocking, suggestion, or
> uncertainty. Style preference alone is not blocking. Verify each finding against
> the code before reporting it. Review directly; do not invoke review skills or
> other agents. State the revision reviewed.
>
> End with one verdict: `APPROVED` (no blocking findings, no material
> uncertainty), `CHANGES_REQUESTED`, or `ESCALATE` (needs a decision or capability
> beyond this review).

Resolve material uncertainty before approval; minor limitations can be recorded
explicitly without blocking.

The host inspects consequential findings and edits; it does not forward verdicts
blindly. Challenge unsupported findings with evidence and seek reconciliation or
another opinion if needed. Do not waive a verified defect or required failed
check to finish faster. Avoid rerunning unchanged checks merely to duplicate
another agent's evidence; spot-check when freshness, trust, or coverage is in doubt.

If review finds a defect, repair it, refresh affected verification, then return
the repaired areas to review. If a defect is discovered after final checks,
the completion claim must wait for the relevant evidence to be refreshed.
The same reviewer may verify repairs to its own findings. Use a fresh reviewer
for materially changed scope, a disputed finding, or a new review question.

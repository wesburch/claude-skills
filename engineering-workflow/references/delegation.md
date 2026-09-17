# Delegation and review

One agent may implement locally or coordinate workers. Do not spawn a duplicate
coordinator. Implementation authors cannot independently review their own diff;
the host may review a worker's change if the host did not author it. A reviewer
can run checks and inspect visual behavior; these do not require another agent.
If the host edits the diff, assign independent review elsewhere.

## Handoff packet

Give a fresh agent only the context needed to execute:

- Repo/cwd, objective, requirements, acceptance criteria.
- Assignment type: implementation, investigation, or independent review.
- Owned files or bounded search area; exclusions and relevant references.
- Baseline and relevant committed, staged, unstaged, and untracked changes.
- Permitted actions, tools, chosen model/effort, and task-specific time budget.
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
- Expected compact return and stop conditions.

Do not attach the full parent transcript. Reviewers receive requirements and
evidence without depending on the implementer's reasoning narrative. Workers
do not recursively delegate unless the host explicitly assigns bounded fan-out.
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

## Independent review

Review the actual final change against requirements, correctness, meaningful
test coverage, and relevant regression/security risks. Check evidence freshness.
Use one reviewer for ordinary work. Add a specialist only for a distinct
unresolved risk, not for a generic second sweep.

Return `APPROVED`, `CHANGES_REQUESTED`, or `ESCALATE`. Findings include location,
observed behavior, violated requirement/contract, and evidence or reproduction.
Separate blocking defects, optional suggestions, and unresolved uncertainty.
Stylistic preference alone is not a blocking defect. Resolve material uncertainty
before approval; minor limitations can be recorded explicitly without blocking.

The host inspects consequential findings and edits; it does not forward verdicts
blindly. Challenge unsupported findings with evidence and seek reconciliation or
another opinion if needed. Do not waive a verified defect or required failed
check to finish faster. Avoid rerunning unchanged checks merely to duplicate
another agent's evidence; spot-check when freshness, trust, or coverage is in doubt.

If review finds a defect, repair it, refresh affected verification, then return
the repaired areas to review. If a defect is discovered after final checks,
the completion claim must wait for the relevant evidence to be refreshed.

# State machine

Nine states. Applies fully to `standard` and `full`; `quick` uses a reduced
subset (see below). Mechanical transitions (verification's pass/fail routing)
don't require frontier-model reasoning — everything else is a role decision
and gets written down by the role that made it.

## States

| State | Assertion |
|---|---|
| `PLANNED` | The task exists. Spec/acceptance criteria may still be incomplete. |
| `READY` | Spec, acceptance criteria, non-overlapping ownership, and the evidence bundle (which commands/checks will run) are written down. An implementer can start without asking a question. |
| `IMPLEMENTING` | A named implementer holds the task. The diff is moving. |
| `VERIFYING` | The implementer declared the diff final for this round. The verifier's declared checks are running or have run. |
| `REVIEW` | Every declared check for *this exact diff* passed. A named independent reviewer holds the packet. |
| `FIXING` | A reviewer returned at least one BLOCKING finding. The original/designated implementer holds the task. **Verification failures never land here** — those go to `IMPLEMENTING`. |
| `APPROVED` | A reviewer returned APPROVED against this diff, with no open BLOCKING findings. |
| `BLOCKED` | Progress needs something outside the task: a user decision, a missing input, an external dependency. Records the state it will return to. |
| `MERGED` | Terminal. The coordinator/supervisor merged per the project's own merge rules. |

## Legal transitions

```
PLANNED      -> READY | BLOCKED
READY        -> IMPLEMENTING | BLOCKED
IMPLEMENTING -> VERIFYING | BLOCKED
VERIFYING    -> REVIEW        (every declared check PASS)
             -> IMPLEMENTING  (any declared check FAIL or INCOMPLETE)
             -> BLOCKED
REVIEW       -> APPROVED      (verdict APPROVED, no open BLOCKING findings)
             -> FIXING        (verdict CHANGES_REQUESTED, >=1 BLOCKING finding)
             -> BLOCKED
FIXING       -> VERIFYING     (the only exit — evidence always reruns)
             -> BLOCKED
APPROVED     -> MERGED
             -> VERIFYING     (the diff changed after approval — approval is void)
             -> BLOCKED
BLOCKED      -> the state recorded at block time, or READY
MERGED       -> (terminal)
```

The two return paths to the implementer (`IMPLEMENTING` from a failed
verification, `FIXING` from a BLOCKING review finding) are deliberately
different states for the same person. A task that went through `FIXING` was
*reviewed*; a task that only bounced through `IMPLEMENTING` was not. Collapse
them and a later reader can no longer tell whether a human/reviewer judgment
ever happened, from the log alone.

## Explicitly illegal transitions

Naming these matters more than the legal list — each is the shortcut someone
under time pressure reaches for:

- `IMPLEMENTING -> REVIEW` — review with no evidence.
- `FIXING -> REVIEW` — re-reviews a repair whose evidence never reran.
- `VERIFYING -> FIXING` — records a verification failure as if a reviewer had
  raised it. No review happened; the task goes to `IMPLEMENTING`.
- `VERIFYING -> APPROVED` — a green build is not a review.
- `REVIEW -> MERGED` — merges on a verdict's tone rather than the verdict.
- anything `-> MERGED` other than from `APPROVED`.
- `APPROVED` surviving a diff change — approval binds to a diff, not a task.

## Quick's reduced subset

`quick` doesn't distinguish `FIXING` from `IMPLEMENTING` (there's no
reviewer to raise a BLOCKING finding) and skips `REVIEW`/`APPROVED` as
distinct machine states — it uses:

```
READY -> IMPLEMENTING -> VERIFYING -> IMPLEMENTING (on FAIL, loop)
                                    -> done (on PASS; human review / MERGED per project rules)
```

If a quick task turns out to need real review, escalate to `standard` and
adopt the full machine from wherever it currently sits — don't retrofit
`FIXING` onto a quick task after the fact.

## The task artifact

One artifact per task holds this state, the transition log, ownership set,
evidence, and review rounds. Append-only transition log — a state that
changed without a logged line is a state nobody can audit later.

Default location and shape, unless project config
(`references/project-config.md`) says otherwise: `docs/evidence/tasks/<TASK-ID>.md`,
a flat Markdown file — inspectable with `cat`, diffable, survives a crashed
pane or a fresh coordinator with zero other context. This default is carried
over from a workflow that ran this exact nine-state shape in production; it
is not a new invention, and a project is free to point it elsewhere via
config.

The knowledge handoff (`references/knowledge-handoff.md`) is one more
append-only section in this same artifact, written at `APPROVED` — not a
separate file, not a separate mechanism.

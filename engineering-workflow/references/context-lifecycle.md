# Context lifecycle

When the primary session should continue, compact or move to a fresh session,
and what crosses the boundary. Delegates follow [delegation.md](delegation.md).
Model choice is a separate decision ([routing.md](routing.md)).

## Objective

Work belongs to the same objective when it is judged by the same acceptance
criteria, or when one part cannot finish without the other's unresolved
reasoning. An implement, test, review and repair loop is one objective. An
objective ends when its criteria are met and its conclusions are durable:
recorded outside the conversation at a known revision.

Commits, PRs and milestones are not objective boundaries by themselves. A merged
change whose CI then fails is the same objective; one PR can hold several. A
completed milestone is a candidate boundary once its conclusions are durable.
Sharing a subsystem or an owner does not make work the same objective. A model
change alone is not an objective boundary; runtime constraints may still
require a restart.

## What the session holds

| State | Meaning | At a boundary |
|---|---|---|
| Live | Unresolved hypotheses, an active failure, open decisions, findings under repair | Keep, or write down before leaving |
| Settled | Decisions made, facts established, committed code | Lives with its owner; the handoff points to it |
| Debris | Logs, superseded snapshots, resolved investigations, repeated output | Drop |
| Stale | Rejected designs, false hypotheses, state that contradicts disk or HEAD | Drop; harmful if kept |

## When to assess

Assess only at a checkpoint:
- acceptance criteria are met or a milestone is reached;
- the user names a new objective;
- ownership or role changes;
- a pollution symptom appears;
- the runtime requires a restart: configuration, hooks or tools that load only
  at session start, or a different directory or machine.

Otherwise continue without comment. Context-size warnings and repeated automatic
compaction call for a compaction assessment only; they never define a boundary.

Pollution symptoms:
- the user has corrected the same misunderstanding more than once;
- a rejected or deferred approach is proposed again;
- cited file contents or state contradict disk or HEAD;
- an abandoned design still dominates the conversation;
- conclusions conflict with no recorded resolution;
- the next step is a critical judgment of something this session built.

## Decide, in order

1. **Independence.** Review of work this session authored goes to another
   instance ([delegation.md](delegation.md)); this session continues as host.
2. **Durability.** Before any boundary, settled state is recorded at a known
   revision and reachable from where the next session starts. Otherwise record
   it first: update task state, propose a commit, or write the handoff.
3. **Runtime restart required:** handoff, then a fresh session.
4. **Pollution:** write the live state down, then a fresh session, even for
   related work.
5. **Live state the next step needs that exists only here:** continue; compact
   when debris dominates.
6. **New objective:** recommend a fresh session when the current context does
   not serve it. A small objective in a clean session may simply continue.
   QUICK work needs no formal handoff merely because it is small; the
   bootstrap prompt can carry it.
7. Otherwise continue.

Each outcome is a recommendation. The user ends, clears and compacts sessions.
State a recommendation once per boundary, and drop it if the user declines.

## Compact

Compaction keeps live state and pointers to settled state, and drops debris.
Keep the objective and its criteria, revision and working-tree state, live
hypotheses with their evidence, open decisions, rejected approaches likely to
recur (one line each), the next action and constraints. Re-read files from disk
rather than carrying them.

Compaction is lossy: first record any settled decision or subtle live
hypothesis with its owner. Then use the runtime's command with a focus
instruction naming what to keep (Claude Code `/compact <focus>`; Codex
`/compact`). Automatic compaction may happen anyway; keeping state durable at
milestones limits what it can lose.

Compaction keeps the session's framing, so it does not cure pollution. When the
live state has been recorded and the next step needs only settled state, a
handoff and a fresh session can substitute for compaction, including where the
runtime has no compact command.

## Handoff

Pointers, not copies; one screen.

Required:
- **Describes:** repo, branch, commit, and working-tree state (clean, or what is
  uncommitted and why).
- **Next objective:** one sentence and its done-when criteria, a pointer to
  them, or "to define with the user".
- **Boundary:** one line on why a fresh session.
- **Read first:** 3–8 paths in order, each with what to read it for.
- **Open:** unresolved questions with who decides (user or agent), and items
  the owner deferred or ruled out of scope.
- **Baseline:** commands that re-establish it. Record a result only together
  with the commit it was observed at.

When applicable:
- settled decisions not yet recorded by their owner, one line each (many means:
  record them there first);
- rejected approaches the next agent is likely to propose again, with the reason;
- constraints and authorization limits;
- suggested profile and capability class (a model only if the user chose one);
- suggested discipline, where useful for the next objective;
- private context, named by role and never by path in a public artifact;
- known failures that affect the next objective;
- one line of friction that a pointer or check would remove.

Leave out narrative, logs, diffs, file snapshots, unpinned counts or results,
and anything the repository, `git log` or `--help` already answers. Redact
secrets.

### Where it lives

- Existing task state or tracker, or `task_store`
  ([project-config.md](project-config.md)), when available.
- FULL: the task artifact's `next` and `open` state is the handoff; write no
  second document.
- STANDARD without durable task state: put the handoff in the completion output
  for the user to paste into the fresh session.
- Persist a handoff file only when cross-session durability requires it. Put it
  on the branch the next session starts from; replace it rather than adding
  another.

### Bootstrap prompt

End with a short prompt for the user to paste:
- repo and branch;
- where the handoff is, or the handoff itself;
- an instruction to check HEAD against the commit it describes;
- the objective and the mode;
- what not to load.

The user starts the new session.

## Checks

Producer, before recommending a fresh session:

```
git status --porcelain
git ls-files --error-unmatch <handoff>   # a persisted handoff is tracked on the start branch
```

Consumer, at the start:

```
git merge-base --is-ancestor <commit> HEAD
git log --oneline <commit>..HEAD
git status --porcelain
```

Report drift between the handoff and the repository before acting; the
repository wins.

## Where facts belong

One owner per fact; other places point to it.

| Owner | Holds |
|---|---|
| Conversation | Live reasoning; nothing settled once a boundary is reached |
| Handoff | Next objective, start point, open and deferred items, pointers |
| Task state | Progress, remaining work, frontier, blockers |
| Git | Code and change history; commit or PR text where useful |
| Domain glossary (`GLOSSARY.md`) | Durable domain terms and meanings, when needed |
| ADR | Architecture decisions, under the project's convention (`decisions_store`) |
| AGENTS.md, project instructions | Rules every future session needs |
| Project docs and knowledge | Durable facts and design rationale ([knowledge-handoff.md](knowledge-handoff.md)) |
| Private evaluation evidence | Tasks, hidden answers, runs, traces; public files name it by role |
| Personal wiki | Lessons beyond one project, routed by project-knowledge |

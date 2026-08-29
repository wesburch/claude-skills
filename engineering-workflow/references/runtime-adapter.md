# Runtime adapter

The workflow's roles, states, and loop must survive a future move off
today's runtime. Every place else in this Skill talks about "spawning" or
"dispatching" an agent in the abstract — this file is the only place that
should ever name a concrete runtime, and it names two: Herdr (preferred when
present) and this CLI's own native agent dispatch (the fallback, and often
simpler when Herdr isn't running).

## The abstract operations

Six operations cover everything a profile needs from a runtime:

| Operation | Does |
|---|---|
| `spawnAgent(role, task)` | Start a new agent instance holding one role for one task. |
| `sendTask(agent, context)` | Give a running/new agent its task context (spec, packet, prior state). |
| `awaitCompletion(agent)` | Block or poll until the agent reports done. |
| `inspectStatus(agent)` | Check whether an agent is running, idle, done, or stuck, without waiting. |
| `collectResult(agent)` | Retrieve the agent's output/verdict/artifact. |
| `stopAgent(agent)` | Tear down an agent instance that's done or no longer needed. |

Nothing in `profiles.md`, `roles.md`, or `state-machine.md` should ever need
to know which runtime implements these. If you find yourself writing "start
a Herdr pane" inside one of those files, that's a layering violation — move
it here instead.

## Herdr (current default when available)

Herdr is a pane/tab/workspace organizer with agent recognition and a CLI.
Map the six operations onto it:

| Operation | Herdr mapping |
|---|---|
| `spawnAgent` | Create a sibling pane (default: current tab, current cwd, unless the profile needs a separate worktree — e.g. non-overlapping ownership sets in `full`) and start the role's agent in it. |
| `sendTask` | Send the task/context into that pane (the packet a role needs — see `roles.md` for what each role receives). |
| `awaitCompletion` | Poll or wait on the pane/agent's reported status. |
| `inspectStatus` | Query the pane's/agent's current status without blocking. |
| `collectResult` | Read the agent's output from the pane, or — preferably — from the task artifact it wrote to (`state-machine.md`), which survives a crashed pane the scrollback doesn't. |
| `stopAgent` | Close the pane / stop the agent when its role is done. |

Use `--no-focus` (or the equivalent for background work) unless the user
asked to switch context to it. Default to a sibling pane in the current tab
and the current working directory — don't create a new workspace, tab,
worktree, or cwd unless the profile's ownership rules require it (`full`'s
non-overlapping file sets) or the user explicitly asks.

## Native fallback — this CLI's own agent dispatch

When Herdr isn't running, or for a runtime that dispatches agents directly
(a plain Claude CLI or Codex CLI session, an SDK-based orchestrator):

| Operation | Native mapping |
|---|---|
| `spawnAgent` | Dispatch a fresh subagent for the role (a non-fork dispatch — each role should start with zero shared context except what `sendTask` gives it, per `roles.md`'s "reviewer doesn't see the implementer's reasoning transcript" rule). |
| `sendTask` | The dispatch prompt itself — self-contained, since a fresh agent has no memory of the coordinating session. |
| `awaitCompletion` | Wait for the dispatch's completion notification. |
| `inspectStatus` | Check whether the dispatch is still running. |
| `collectResult` | Read the dispatch's final report, or the task artifact it wrote. |
| `stopAgent` | Stop/cancel a dispatch that's no longer needed. |

A single session running a `quick` profile solo (implementer only, no
coordinator) doesn't need any of this — it just does the work and runs
verification itself.

## Resolving which adapter to use

1. Project config (`project-config.md`) may declare a `runtime` preference.
2. Otherwise, detect what's actually available in the current environment.
3. If genuinely ambiguous and it matters (`full` profile, real parallelism
   at stake), ask rather than guess.

## Adding a new runtime later

A new runtime adapter is a new mapping table in this file — nothing in
`profiles.md`, `roles.md`, `state-machine.md`, or `model-routing.md` should
need to change. If adding one *does* require touching those files, that's a
sign something runtime-specific leaked into the portable layer; fix the
leak, not the new adapter.

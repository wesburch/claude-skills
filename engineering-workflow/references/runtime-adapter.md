# Runtime adapters

Resolve only when dispatching: explicit user/project choice, then suitable
capabilities in the active host. Prefer native dispatch when it meets the task.
Installed binaries do not prove authentication, model access, or active sessions.
Do not install a proxy or change global defaults just to satisfy a routing table.

Every adapter must start a scoped assignment, deliver its packet, await or
inspect completion, collect results, and stop/cancel when necessary. Completion
means an actual result and successful process/tool status, not merely a pane
that looks idle. Keep the user informed during long work; use notifications or
bounded waits rather than frequent polling.

## Native agents

Use the host's documented dispatch controls, selecting model and effort explicitly
where exposed. Start with a fresh context (`fork_turns: "none"` in runtimes that
support it). Do not copy a transcript to compensate for an incomplete packet.
For Claude native dispatch, use supported model selectors; for Codex, use the
exposed model/effort fields or verified agent configuration. If a runtime cannot
override them, disclose inheritance instead of claiming economical routing.

Pass only the assigned role and required instructions to children so they do not
restart the entire workflow. Keep worker fan-out bounded by available slots and
the task; children do not automatically become coordinators.

## Native provider CLIs for cross-provider work

Check the actual binary's version and help before constructing a command. Use
the correct repo directory and an explicit supported model. Read current official
guidance only when local help leaves an execution question unresolved.

Codex CLI commonly supports `exec`, `--model`, `--sandbox read-only`, `--cd`,
`--output-last-message`, `--json`, and `-c model_reasoning_effort=...`; verify
against the installed version. Feed the packet through stdin (`-`). For Claude,
verify print/headless mode, model and tool restrictions, and supported effort
options from its installed help. Do not assume flags are identical across CLIs.

Pass arbitrary prompts through stdin or a safely handled file, never interpolate
them into shell commands. Use a unique temporary directory for stdout, stderr,
and result artifacts. Apply a bounded timeout, inspect exit status and output,
and resolve possibly live processes after timeout before retrying or editing
their files. Empty output, permission denial, or a timeout is not success.

For review/research, enforce read-only project access and restrict external
write-capable tools as well; a prompt saying "read-only" is not enforcement.
For edits, use scoped write permissions, preserve existing user changes, and
isolate conflicting work when the runtime supports it. Do not bypass permission
controls. If required restrictions cannot be established, use a supported native
alternative or return the prepared handoff and the limitation.

Host inspection and appropriate checks complete the handoff. Retry/escalation
follows [routing.md](routing.md), not an automatic provider-failover chain.

## Managed terminals and worktrees

Use the relevant available runtime skill when the user/project explicitly chooses
Orca or Herdr, or work touches their managed state. Respect its environment and
ownership requirements. Neither wins merely by being installed.

Map spawn/send/wait/status/result/stop to that runtime's documented operations.
Prefer completion artifacts or structured status to parsing terminal prose.
Do not close a user-owned pane as worker cleanup. Use an isolated worktree when
concurrent edits would conflict; independent work in disjoint files may share a
workspace if integration and evidence freshness remain controlled.

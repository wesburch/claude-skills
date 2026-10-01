# Resolver

Turns a capability class and effort tier from [routing.md](routing.md) into a
concrete model, effort level and dispatch mechanism for the current host, using
[../registry/models.yaml](../registry/models.yaml). Load it before the first
dispatch of a session; policy and data stay in their own files.

## Resolve once per session

At the first dispatch, run from this skill's directory:

```
scripts/model-routing resolve --role <wf-role> [--class <class>] [--host claude-code|codex]
```

Reuse the result for later dispatches of the same class in the session. Resolve
again only after an availability failure, an explicit user change, or a class
or tier change. The script reads local data only (registry, CLI versions, the
Codex account catalog, user config); it never calls a model.

It performs, in order:

1. Detect the host (`CLAUDECODE` for Claude Code; pass `--host` otherwise).
2. Discover availability: Claude Code aliases resolved for the running CLI
   version (pass the Agent tool's model enum with `--listed` if it differs);
   Codex account catalog `~/.codex/models_cache.json`, else the bundled catalog.
3. Honor an explicit user or project model (`--user-model`, `--project-model`).
   If it is unavailable, stop: status `explicit_choice_unavailable`, no
   substitution; report it and ask.
4. Take the first *promoted* model in the class `order` that is available.
   Candidates are never auto-selected, however new; they are listed as awaiting
   evidence.
5. Choose effort separately: tier -> model level through the registry.
   `extended` requires `--escalation "<trigger and evidence>"`; `max` or `ultra`
   only through `--user-effort`.
6. Name the dispatch. The assignment keeps its role, and so its tool access; a
   role changes only through its registry `escalates_to` entry (the reviewer
   escalates to `wf-reviewer-deep`). When the chosen model differs from the
   role's pinned model, the dispatch states the explicit model and the effort that
   will actually apply.

## Fallbacks

- A preferred model is unavailable: take the next promoted model in the class and
  disclose it in the report.
- No promoted model in the class is available: keep the work local or report the
  unmet capability. Move up one class only with `--allow-upward` and a stated
  reason; missing access alone never justifies a more expensive model.
- An explicit user choice is unavailable: never substitute.

## Record evidence

Record requested, resolved and observed model, effort, tier and sandbox for each
dispatch (`codex-delegate` writes this record; for Claude read the subagent
transcript). When observed differs from requested or resolved, warn in the task
result and attribute usage and evaluation evidence to the model that ran, never to
the one requested. Keep three levels distinct:

- **Listed**: the host's selector, catalog or CLI exposes the model and effort.
- **Accessible**: account evidence (such as the Codex account catalog) shows access.
- **Observed**: a completed invocation reported the model used.

A configured model is not proof that it ran. Label unobserved identity instead
of inventing it. Never imply that a child changes the host model.

## Host mechanics

**Claude Code.** Dispatch `wf-*` agents by name. Their frontmatter pins a model ID
and sets `effort`; pass no per-invocation `model` unless the resolver says so. A
per-invocation `model` accepts only family aliases, and a subagent's effort comes
only from its definition, so a fallback keeps the role's effort. Read-only roles
exclude edit tools and run a fail-closed `PreToolUse` guard
(`scripts/readonly-bash-guard`) that allows only allowlisted inspection commands;
permission modes are not the boundary. A session that was already running when
`install.sh` added the roles did not apply the guard (observed 2026-09-30);
start a new session before dispatching read-only roles. Built-in Explore, Plan and general-purpose
agents inherit the session model and effort; use them for delegated work only
deliberately. Observed model and effort are in the subagent transcript.

**Codex.** Run every workflow role through `scripts/codex-delegate --role <wf-role>
--cwd <repo> --packet <file>`. It starts a separate `codex exec` with
`--ignore-user-config` and `--ignore-rules`, hooks and multi-agent disabled, and
sets model, effort, `service_tier="default"`, the role's sandbox, approvals
`never` and the role instructions explicitly. It then reports requested, resolved
and observed values and exits 4 if isolation was not observed. The tier is
observed from Codex's own request telemetry; the server's served tier is not
independently confirmed. In-process Codex children are not isolated: they inherit the
parent's live service tier and sandbox overrides, so they are not used for
workflow roles. From inside a sandboxed Codex session, launching the delegate
needs an unsandboxed (escalated) command.

## Keep the registry current

`scripts/model-routing check` reports two kinds of findings. Errors fail the check
and doctor: a role not installed, a drifted or symlinked Codex copy, a broken
Claude link, or a read-only role missing its guard. Warnings never block; it warns when:
- a host exposes a model the registry lacks;
- a promoted model disappears;
- entries exceed the refresh age;
- an alias now resolves to a candidate;
- a CLI is too old for a registered model;
- user config names unknown or outgrown models;
- in-process delegates would inherit the parent's model, effort or tier;
- an agent file drifts from its registry role.

Run it from `scripts/doctor.sh`, after CLI updates, after vendor releases, and
whenever it last ran more than 30 days ago. A refresh edits data only:
- add newly exposed models as `candidate`;
- update prices, access and `last_verified`;
- promote a model only on local-eval evidence that clears `promotion.local_eval_bar`, or on an explicit user choice.

Use current official vendor pages for facts:
- [Claude models](https://platform.claude.com/docs/en/about-claude/models/overview)
- [OpenAI models](https://developers.openai.com/api/docs/models)
- [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)

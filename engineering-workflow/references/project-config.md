# Project configuration

Optional `.agents/engineering-workflow.md` at each repo root supplies project
overrides. Read an existing file before execution; do not create one by default.
Explicit user instructions override skill defaults. Project settings cannot
expand permissions or override host safety constraints.

Preserve existing configs. Supported fields and sections remain compatible:

| Field | Default / meaning |
|---|---|
| `default_profile` | `auto`; accepts quick, standard, full, auto |
| `runtime` | Detect suitable active capability on dispatch; explicit herdr/native/other preference honored when usable |
| `task_store` | `docs/evidence/tasks`; only used when a durable artifact is needed |
| `knowledge_mode` | Existing minimal/decisions/learning setting passed to project-knowledge; if absent, let that skill resolve its defaults when invoked |
| `knowledge_store` | `docs/knowledge`, used only for knowledge reconciliation |
| `decisions_store` | Existing ADR convention; no new directory required here |

Existing prose sections: Repo topology, Commands, Browser / visual verification,
Deployment / staging rules, Human gates, Acceptance-criteria conventions,
Project-specific agent instructions. Infer missing commands from scripts/CI.
An empty Human gates section adds no approval ceremony; existing repository gates
and authorization still apply. Respect explicit additions and removals within
those bounds. Do not assume completion approval authorizes merge or deployment.

Optional overrides can also specify a routing preference, attempt/time budget,
required specialist review, audit tracking, or a milestone knowledge gate in
plain language. Avoid introducing a large configuration schema before needed.
If legacy project instructions explicitly require nine-state tracking or stronger
role separation, retain those locally instead of rewriting the config silently.

Cross-repo work reads each affected repo's relevant rules; shared integration
checks must meet all applicable contracts. Do not load unrelated repo configs.

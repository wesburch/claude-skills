# Project configuration

The portable workflow carries no project-specific defaults. Everything a
project needs to supply lives in one optional file, read by both
`engineering-workflow` and `project-knowledge` (see that Skill's own
reference to the same file) — one config, not two.

## Location

`.agents/engineering-workflow.md` at the repo root.

This deliberately does **not** follow `briefme`'s `.claude/brand.json`
precedent. `briefme` is Claude-Code-specific and its config path reflects
that. This workflow is explicitly meant to run from Claude CLI, Codex CLI,
Herdr-driven sessions, and future runtimes — a config path scoped to one
provider's directory would misrepresent that as Claude-owned config the way
`.claude/settings.json` is. `.agents/` is provider-neutral: Claude and Codex
both read from it as the same project-local configuration, and neither
implies ownership over it.

If it doesn't exist, don't create it automatically — proceed on the defaults
below, and only suggest creating one if the user is repeatedly overriding the
same thing.

## Shape

YAML frontmatter for fields the workflow reads mechanically; prose sections
below it for anything that needs explaining rather than a value.

```markdown
---
default_profile: standard        # quick | standard | full | auto (default: auto)
runtime: herdr                   # herdr | native | <other> (default: detect)
task_store: docs/evidence/tasks  # where task artifacts live (default shown)
knowledge_mode: learning         # minimal | decisions | learning (see project-knowledge)
knowledge_store: docs/knowledge  # where project-knowledge writes (see project-knowledge)
decisions_store: docs/decisions  # existing ADR dir, if the project already has one
---

## Repo topology
<single repo / monorepo layout / multi-repo list>

## Commands
- build: <command>
- test: <command>
- lint: <command>
- typecheck: <command>

## Browser / visual verification
<how the Verifier should check visual/browser state for this project, if applicable>

## Deployment / staging rules
<what "ready to merge" or "ready to deploy" means here, if not just APPROVED>

## Human gates
<any point in the loop that needs a human, beyond the sensible defaults below —
list additions, removals, or full replacements explicitly; an empty section
means the defaults apply as-is>

## Acceptance-criteria conventions
<how this project writes/derives acceptance criteria, if it has a house style>

## Project-specific agent instructions
<anything a role needs to know about this codebase that isn't discoverable from the code itself>
```

Every field is optional. A project that only cares about overriding
`default_profile` writes three lines of frontmatter and nothing else.

## Defaults when absent or a field is unset

| Field | Default |
|---|---|
| `default_profile` | `auto` — recommend per `profiles.md` |
| `runtime` | detect per `runtime-adapter.md` |
| `task_store` | `docs/evidence/tasks` |
| `knowledge_mode` | `learning` for a personal project, `decisions` otherwise — ask if genuinely unclear which this is |
| `knowledge_store` | `docs/knowledge` |
| `decisions_store` | none — `project-knowledge` looks for a conventional ADR directory (`docs/decisions`, `docs/adr`) itself before falling back |
| Commands | infer from the repo (`package.json` scripts, a `Makefile`, a `justfile`, CI config) rather than ask, unless genuinely ambiguous |
| Human gates | see below — these are sensible defaults, not universal hardcoded policy |

## Human gates are project-configurable, not hardcoded policy

The workflow ships with default human-escalation triggers so a project with
no config still behaves reasonably — see `roles.md`'s escalation sections for
the full default list (ambiguous requirements, conflicting evidence/
dependencies, repeated repair-loop failure, low coordinator/reviewer
confidence for a coordinator/reviewer escalating; destructive operations,
credentials/signing/network services or a new external provider, a material
scope expansion, or a product/architecture call that changes the visible
experience or evidence claim, for a root supervisor escalating to the user).
Quick's completion step is always at least a human-review gate by default;
standard/full otherwise gate at merge per whatever the repo's own branch/PR
rules already require.

**None of that is universal policy — it's what applies when a project hasn't
said otherwise.** A project's `## Human gates` section can add gates
(require a human sign-off before merge regardless of approval, require one
before touching a specific directory), remove ones that don't apply (a
solo personal project with no external provider risk may not need the
credentials/signing gate spelled out), or replace the list outright. When
`## Human gates` says something, it wins over the defaults in `roles.md` for
that project — those defaults are a starting point, not a ceiling or floor.

## What does not belong here

Don't hardcode a specific project's fields as if they were the portable
default — this file describes the *contract*, not any one project's values.
If you're editing this reference to add a real project's actual commands or
paths, you've confused the config file with the schema that describes it;
put real values in that project's own `.agents/engineering-workflow.md`
instead.

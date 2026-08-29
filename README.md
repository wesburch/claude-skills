# Claude Code Global Skills

A collection of reusable global skills for [Claude Code](https://claude.ai/code) that can be shared across machines and projects.

## What are Global Skills?

Global skills are custom commands (invoked with `/skill-name`) that extend Claude Code's capabilities. Unlike project-specific skills, global skills work in any directory and are available across all your coding sessions.

## Installation

### On a New Machine

1. **Clone this repository:**
   ```bash
   cd ~
   git clone git@github.com:wesburch/claude-skills.git
   ```

2. **Run the installer:**
   ```bash
   ~/claude-skills/scripts/install.sh
   ```
   This symlinks every skill directory (one with a `SKILL.md`) into
   `~/.claude/skills/` and `~/.codex/skills/`, and every file in `commands/`
   into `~/.claude/commands/`. It's idempotent and non-destructive — safe to
   rerun any time (e.g. after `git pull` or adding a new skill). It never
   overwrites a real file or directory; if something else already occupies a
   target path, it's reported as a conflict for you to resolve by hand
   instead of being clobbered.

3. **Verify installation:**
   ```bash
   ~/claude-skills/scripts/doctor.sh
   ```
   Checks that every skill/command in this repo is correctly symlinked into
   Claude and Codex, and that the repo's git state is clean and in sync with
   `origin`. Exits non-zero if anything needs attention. It only checks
   skills defined in this repo — it doesn't know about unrelated skills
   installed some other way (see [Duplicated/managed elsewhere](#a-note-on-other-skills-on-this-machine)
   below).

<details>
<summary>What the installer does manually, if you'd rather not run a script</summary>

```bash
# Skills
cd ~/.claude/skills
for skill in ~/claude-skills/*/; do
  skill_name=$(basename "$skill")
  [[ "$skill_name" == "commands" || "$skill_name" == "scripts" ]] && continue
  ln -s "$skill" "$skill_name"
done

# Same again, but into ~/.codex/skills instead of ~/.claude/skills

# Slash commands
cd ~/.claude/commands
for cmd in ~/claude-skills/commands/*.md; do
  ln -s "$cmd" "$(basename "$cmd")"
done
```
</details>

## Codex (GPT) Installation

Codex reads skills from `~/.codex/skills/<name>/SKILL.md` and slash commands from
`~/.codex/prompts/*.md`.

```bash
# 1. Skills — auto-trigger on shape (wiki, spec, briefme, ...)
#    scripts/install.sh does this for every skill in this repo, Codex included.
~/claude-skills/scripts/install.sh

# 2. Slash commands — /wiki-ingest, /wiki-query, /wiki-lint
#    These are generated wrapper prompts (not symlinks), so they aren't
#    managed by install.sh. Only needs to be (re-)run if the wiki skill's
#    sub-command names change.
mkdir -p ~/.codex/prompts
for op in ingest query lint; do
  printf 'Use the `wiki` skill. Read `~/.codex/skills/wiki/SKILL.md`, then follow\n`~/.codex/skills/wiki/references/%s.md` in full against the wiki at\n`~/Documents/MyProjects/wiki/`.\n\nArgument: $ARGUMENTS\n' "$op" > ~/.codex/prompts/wiki-$op.md
done
```

Verify with:
```bash
cd ~/claude-skills && codex exec --sandbox read-only --skip-git-repo-check \
  "List the exact names of every skill available to you, one per line."
```

## Available Skills

### `wiki` (Codex skill + `/wiki-*` prompts)
**Description:** Ingest, query, and lint the personal wiki at `~/Documents/MyProjects/wiki/`.
`SKILL.md` routes to `references/{ingest,query,lint}.md`. Kept current with the wiki's own
`CLAUDE.md` — no `tags:` frontmatter, `make reindex` (= `qmd update` + `qmd embed`), and
category `index.md` maps must be updated on write.

### `/wiki-query` - Query the Wiki
**Description:** Answer a question from the personal knowledge base at `~/Documents/MyProjects/wiki/`.

### `/wiki-ingest` - Ingest a Source into the Wiki
**Description:** Add a new source (file, URL, or pasted text) to the wiki, creating/updating pages and updating the index.

### `/wiki-lint` - Audit the Wiki
**Description:** Health check — finds broken links, orphan pages, missing frontmatter, contradictions, and stale content.

---

### `/spec` - Feature Specification Generator

**Description:** Generate comprehensive feature specifications through an interactive interview process.

**Usage:**
```bash
/spec                           # Start from scratch
/spec notifications             # Generate spec for a feature
/spec notifications Send push notifications when lineup submitted
```

**What it does:**
1. Analyzes your codebase to understand conventions and patterns
2. Interviews you about requirements through focused questions
3. Generates a complete spec document based on your answers
4. Saves to `specs/[feature-name].md` in your project

**Key Features:**
- Adapts interview based on how much detail you provide upfront
- References existing codebase patterns and similar features
- Includes user stories, acceptance criteria, edge cases, and testing requirements
- Can update existing specs or start fresh

[Full documentation](./spec/SKILL.md)

---

### `/briefme` - Branded HTML Brief Generator

**Description:** Turn agent work into a polished, branded HTML document — status updates, client meeting talking points, or research findings. Pulls brand colors from `.claude/brand.json` in the current repo so each client's brief looks like their brand.

**Usage:**
```bash
/briefme status                 # Dense work log for internal review
/briefme meeting                # Section cards for live client meetings
/briefme research               # Findings deliverable with exec summary
/briefme meeting editorial      # Use a specific theme
/briefme meeting "Optional inline content if not synthesizing from conversation"
```

**Available themes:** `default` (refined editorial), `engineered` (technical / mono-led), `magazine` (bold editorial display), `swiss` (modernist / gridded). See [`briefme/themes/README.md`](./briefme/themes/README.md) for full descriptions and the contract for adding new ones.

**Theme selection:** CLI arg → `brand.json` `theme` field → interactive prompt.

**What it does:**
1. Resolves the repo root and looks up `.claude/brand.json` for the client's colors
2. If brand.json is missing, offers to create one interactively
3. Composes the brief from the conversation (or inline content) using the chosen layout
4. Renders `template.html` with the brand variables substituted
5. Writes to `<repo>/.claude/briefs/<mode>-YYYY-MM-DD-HHMM.html` and opens it in your browser

**Setup per client:** drop a `brand.json` in the project repo's `.claude/` folder. See [`briefme/brand.example.json`](./briefme/brand.example.json) for the schema.

[Full documentation](./briefme/SKILL.md)

---

## Creating a New Skill

### Basic Structure

Each skill is a directory containing a `SKILL.md` file:

```
skill-name/
└── SKILL.md
```

### SKILL.md Format

```markdown
---
name: skill-name
description: Brief description of what the skill does
argument-hint: "[optional-args]"
---

# Skill Implementation

Your skill prompt goes here. Use standard markdown.

## Arguments

- `$ARGUMENTS[0]` or `$0` - First argument
- `$ARGUMENTS[1]` or `$1` - Second argument
- `$ARGUMENTS[1:]` - Remaining arguments as array

## Example Behavior

Describe what Claude should do when this skill is invoked.
```

### Adding Your New Skill

**Scaffold it:**
```bash
~/claude-skills/scripts/new-skill.sh my-new-skill
```
Creates `my-new-skill/SKILL.md` with the frontmatter above pre-filled and
`TODO` placeholders for the rest. Refuses to run if `my-new-skill/` already
exists, and never touches any other skill.

Options:
- `-d, --description TEXT` — fill in the description field directly instead of a TODO
- `-r, --references` — also create `my-new-skill/references/`, for a skill whose
  `SKILL.md` will route to supporting docs (see `engineering-workflow/references/`
  or `wiki/references/` for examples of the pattern)
- `-h, --help` — usage

Then:
1. **Fill in `SKILL.md`** — description, argument-hint, and steps.
2. **Install it:**
   ```bash
   ~/claude-skills/scripts/install.sh
   ```
   Symlinks it into both `~/.claude/skills/` and `~/.codex/skills/` automatically.
3. **Test it:** open Claude Code and run `/my-new-skill`
4. **Commit and push:**
   ```bash
   cd ~/claude-skills
   git add my-new-skill/
   git commit -m "Add my-new-skill"
   git push
   ```

<details>
<summary>Doing it by hand instead of scripts/new-skill.sh</summary>

```bash
cd ~/claude-skills
mkdir my-new-skill
vi my-new-skill/SKILL.md   # write the frontmatter + prompt yourself
```
</details>

## Skill Development Tips

- **Keep skills focused** - Each skill should do one thing well
- **Make them reusable** - Design skills to work across different projects
- **Use codebase analysis** - Have skills read CLAUDE.md, check file patterns, etc.
- **Provide examples** - Include usage examples in your SKILL.md
- **Handle arguments gracefully** - Make arguments optional when possible
- **Be conversational** - Skills should guide users through the process

## How Skills Work

When you invoke `/skill-name` in Claude Code:

1. Claude reads the `SKILL.md` file from `~/.claude/skills/skill-name/`
2. The skill's frontmatter and content become part of Claude's context
3. Claude follows the instructions in SKILL.md
4. Arguments you provide are available as `$ARGUMENTS` or `$0`, `$1`, etc.

## Contributing

Feel free to fork this repo and create your own skills! If you create something useful, consider sharing it back via a pull request.

## Syncing Across Machines

Since this is a git repository, keeping skills in sync is simple:

```bash
# On any machine
cd ~/claude-skills
git pull
./scripts/install.sh   # picks up any newly added skills/commands
```

## Troubleshooting

Run the doctor script first — it checks everything below in one pass:

```bash
~/claude-skills/scripts/doctor.sh
```

### Skill not appearing in Claude Code or Codex

1. Check the symlink exists and points into this repo:
   ```bash
   readlink ~/.claude/skills/skill-name
   readlink ~/.codex/skills/skill-name
   ```
2. If missing or wrong, rerun `~/claude-skills/scripts/install.sh`.
3. Ensure `SKILL.md` exists and is non-empty:
   ```bash
   cat ~/claude-skills/skill-name/SKILL.md
   ```

### Skill not working as expected

1. Check the SKILL.md frontmatter is properly formatted (YAML between `---`)
2. Verify the `name:` field matches the directory name
3. Test the skill with different arguments to see how Claude interprets them

### A note on other skills on this machine

`~/.claude/skills/` and `~/.codex/skills/` may contain skills that did **not**
come from this repo — e.g. skills installed via a Claude Code plugin
marketplace, or third-party skills pulled in by a separate skill-installer
tool (tracked in its own lockfile, not this repo's git history). `install.sh`
and `doctor.sh` only ever touch/check names that exist as a directory with a
`SKILL.md` in *this* repo, so they won't interfere with those.

## License

MIT - Feel free to use, modify, and share these skills however you like.

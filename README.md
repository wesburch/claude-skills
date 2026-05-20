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

2. **Symlink skills into Claude's config:**
   ```bash
   cd ~/.claude/skills

   # Link individual skills
   ln -s ~/claude-skills/spec spec

   # Or link all skills at once
   for skill in ~/claude-skills/*/; do
     skill_name=$(basename "$skill")
     [[ "$skill_name" == "commands" ]] && continue
     ln -s "$skill" "$skill_name"
   done
   ```

3. **Symlink slash commands into Claude's config:**
   ```bash
   cd ~/.claude/commands

   for cmd in ~/claude-skills/commands/*.md; do
     ln -s "$cmd" "$(basename "$cmd")"
   done
   ```

4. **Verify installation:**
   ```bash
   ls -la ~/.claude/skills
   ls -la ~/.claude/commands
   ```
   You should see symlinks pointing to `~/claude-skills/`

## Available Skills

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

1. **Create the skill directory:**
   ```bash
   cd ~/claude-skills
   mkdir my-new-skill
   ```

2. **Write the SKILL.md:**
   ```bash
   # Create your skill prompt
   vi my-new-skill/SKILL.md
   ```

3. **Symlink it:**
   ```bash
   cd ~/.claude/skills
   ln -s ~/claude-skills/my-new-skill my-new-skill
   ```

4. **Test it:**
   Open Claude Code and run `/my-new-skill`

5. **Commit and push:**
   ```bash
   cd ~/claude-skills
   git add my-new-skill/
   git commit -m "Add my-new-skill"
   git push
   ```

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

# If you added new skills, symlink them
cd ~/.claude/skills
ln -s ~/claude-skills/new-skill new-skill
```

## Troubleshooting

### Skill not appearing in Claude Code

1. Check the symlink exists:
   ```bash
   ls -la ~/.claude/skills
   ```

2. Verify the symlink target is correct:
   ```bash
   readlink ~/.claude/skills/skill-name
   ```

3. Ensure `SKILL.md` exists:
   ```bash
   cat ~/claude-skills/skill-name/SKILL.md
   ```

### Skill not working as expected

1. Check the SKILL.md frontmatter is properly formatted (YAML between `---`)
2. Verify the `name:` field matches the directory name
3. Test the skill with different arguments to see how Claude interprets them

## License

MIT - Feel free to use, modify, and share these skills however you like.

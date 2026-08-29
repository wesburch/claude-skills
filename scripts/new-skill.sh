#!/usr/bin/env bash
# Scaffold a new personal skill directory in this repo, following the same
# conventions as the existing skills (briefme, spec, wiki, ...): a
# kebab-case directory at the repo root containing a SKILL.md with `name`
# and `description` frontmatter, optionally with a references/ subdirectory
# for supporting docs the skill loads on demand.
#
# Never overwrites an existing skill directory. Does not touch any other
# skill. Does not run install.sh or touch git — it only prints what to do
# next.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/new-skill.sh <skill-name> [options]

Scaffold a new skill directory at the repo root with a minimal SKILL.md.

Arguments:
  <skill-name>          Kebab-case name, e.g. "release-notes" (required)

Options:
  -d, --description TEXT  Fill in the SKILL.md description field directly
                           instead of leaving a TODO placeholder
  -r, --references        Also create a references/ subdirectory, for a
                           skill whose SKILL.md will route to supporting docs
  -h, --help               Show this help and exit

Examples:
  scripts/new-skill.sh release-notes
  scripts/new-skill.sh release-notes --references \
    --description "Draft release notes from recent commits. Use when the user asks to write release notes or a changelog."
EOF
}

skill_name=""
description=""
with_references=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--description)
      [[ $# -ge 2 ]] || { echo "error: $1 requires a value" >&2; exit 1; }
      description="$2"
      shift 2
      ;;
    -r|--references)
      with_references=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$skill_name" ]]; then
        echo "error: unexpected extra argument: $1" >&2
        exit 1
      fi
      skill_name="$1"
      shift
      ;;
  esac
done

if [[ -z "$skill_name" ]]; then
  echo "error: missing <skill-name>" >&2
  usage >&2
  exit 1
fi

if [[ ! "$skill_name" =~ ^[a-z][a-z0-9-]*$ ]]; then
  echo "error: skill name must be lowercase kebab-case (e.g. \"release-notes\"), got: $skill_name" >&2
  exit 1
fi

skill_dir="$REPO_ROOT/$skill_name"

if [[ -e "$skill_dir" ]]; then
  echo "error: refusing to overwrite — $skill_dir already exists" >&2
  exit 1
fi

if [[ -z "$description" ]]; then
  description="TODO: one or two sentences on what this skill does and when to use it — name concrete trigger phrases, /commands, or keywords."
fi

title="$(awk -F'-' '{ for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2); print }' OFS=' ' <<<"$skill_name")"

mkdir -p "$skill_dir"

cat > "$skill_dir/SKILL.md" <<EOF
---
name: $skill_name
description: $description
argument-hint: "[TODO]"
---

# $title

TODO: describe what this skill does and how it fits into the rest of this
repo's skills.

## Steps

1. TODO
EOF

if [[ "$with_references" -eq 1 ]]; then
  mkdir -p "$skill_dir/references"
  cat > "$skill_dir/references/README.md" <<'EOF'
Supporting reference docs for this skill, loaded on demand from SKILL.md
rather than kept inline. Delete this file once real reference docs exist —
it's only here so the directory isn't empty (git doesn't track empty dirs).
EOF
fi

echo "Created $skill_dir"
echo
echo "Next steps:"
echo "  1. Edit $skill_dir/SKILL.md — fill in description, argument-hint, and steps"
if [[ "$with_references" -eq 1 ]]; then
  echo "  2. Add reference docs under $skill_dir/references/ and route to them from SKILL.md"
  echo "  3. Run scripts/install.sh to symlink the new skill into ~/.claude/skills and ~/.codex/skills"
  echo "  4. Run scripts/doctor.sh to verify the install"
else
  echo "  2. Run scripts/install.sh to symlink the new skill into ~/.claude/skills and ~/.codex/skills"
  echo "  3. Run scripts/doctor.sh to verify the install"
fi

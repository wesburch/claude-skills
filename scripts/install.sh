#!/usr/bin/env bash
# Symlink every skill in this repo into Claude Code and Codex CLI's skill
# directories, and every commands/*.md into Claude's slash-command directory.
#
# Non-destructive: only ever creates a new symlink or repoints a symlink that
# already points somewhere inside this repo. If the target path exists and is
# a real file/directory (or a symlink pointing elsewhere), it is left alone
# and reported so you can resolve it by hand.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_SKILLS="$HOME/.claude/skills"
CODEX_SKILLS="$HOME/.codex/skills"
CLAUDE_COMMANDS="$HOME/.claude/commands"

linked=0
skipped=0
conflicts=()

# link_one <target_path> <source_path>
link_one() {
  local target="$1"
  local source="$2"

  if [[ -L "$target" ]]; then
    local current
    current="$(readlink "$target")"
    if [[ "$current" == "$source" ]]; then
      skipped=$((skipped + 1))
      return
    fi
    if [[ "$current" == "$REPO_ROOT"/* ]]; then
      # Symlink already managed by this repo, just pointing at something
      # stale (e.g. a renamed skill) — safe to repoint.
      ln -sfn "$source" "$target"
      linked=$((linked + 1))
      return
    fi
    # Symlink exists but points outside this repo — don't touch it.
    conflicts+=("$target (symlink -> $current)")
    return
  fi

  if [[ -e "$target" ]]; then
    # Real file or directory sitting at the target path — never clobber it.
    conflicts+=("$target (real file/directory, not a symlink)")
    return
  fi

  mkdir -p "$(dirname "$target")"
  ln -s "$source" "$target"
  linked=$((linked + 1))
}

echo "Installing personal skills from $REPO_ROOT"
echo

for skill_dir in "$REPO_ROOT"/*/; do
  skill_name="$(basename "$skill_dir")"
  [[ "$skill_name" == "scripts" || "$skill_name" == "commands" ]] && continue
  [[ -f "$skill_dir/SKILL.md" ]] || continue

  link_one "$CLAUDE_SKILLS/$skill_name" "$REPO_ROOT/$skill_name"
  link_one "$CODEX_SKILLS/$skill_name" "$REPO_ROOT/$skill_name"
done

if [[ -d "$REPO_ROOT/commands" ]]; then
  for cmd_file in "$REPO_ROOT"/commands/*.md; do
    [[ -f "$cmd_file" ]] || continue
    cmd_name="$(basename "$cmd_file")"
    link_one "$CLAUDE_COMMANDS/$cmd_name" "$cmd_file"
  done
fi

echo "Linked:  $linked"
echo "Already OK: $skipped"

if [[ ${#conflicts[@]} -gt 0 ]]; then
  echo
  echo "Conflicts (left untouched, resolve manually):"
  for c in "${conflicts[@]}"; do
    echo "  - $c"
  done
  exit 1
fi

echo
echo "Note: Codex slash commands (~/.codex/prompts/*.md) are generated wrapper"
echo "prompts, not simple symlinks, and are not managed by this script. See"
echo "README.md's Codex Installation section."

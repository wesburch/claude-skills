#!/usr/bin/env bash
# Symlink every skill in this repo into Claude Code and Codex CLI's skill
# directories, every commands/*.md into Claude's slash-command directory, and
# every agents/claude/*.md delegate role into ~/.claude/agents (symlinks), and
# every agents/codex/*.toml role into ~/.codex/agents as a real copy (Codex does
# not load symlinked agent files).
#
# Usage: install.sh [--dry-run]   (--dry-run prints what would change)
#
# Non-destructive: only ever creates a new symlink or repoints a symlink that
# already points inside this repo or the managed third-party skills checkout.
# A real file/directory (or a symlink pointing elsewhere) is left alone
# and reported so you can resolve it by hand.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_SKILLS="$HOME/.claude/skills"
CODEX_SKILLS="$HOME/.codex/skills"
CLAUDE_COMMANDS="$HOME/.claude/commands"
CLAUDE_AGENTS="$HOME/.claude/agents"
CODEX_AGENTS="$HOME/.codex/agents"

DRY_RUN=0
case "${1:-}" in
  --dry-run) DRY_RUN=1 ;;
  "") ;;
  *) echo "Usage: $0 [--dry-run]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "Usage: $0 [--dry-run]" >&2; exit 2; }

source "$REPO_ROOT/scripts/third-party.sh"
load_third_party
# Preflight/update the pinned checkout before installing any links.
prepare_matt_checkout

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
    if [[ "$current" == "$REPO_ROOT"/* || "$current" == "$MATT_CHECKOUT"/skills/* ]]; then
      # Symlink already managed by this repo, just pointing at something
      # stale (e.g. a renamed skill) — safe to repoint.
      if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  would repoint $target -> $source"
      else
        ln -sfn "$source" "$target"
      fi
      linked=$((linked + 1))
      return
    fi
    # Unmanaged symlink — do not touch it.
    conflicts+=("$target (symlink -> $current)")
    return
  fi

  if [[ -e "$target" ]]; then
    # Real file or directory sitting at the target path — never clobber it.
    conflicts+=("$target (real file/directory, not a symlink)")
    return
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  would link $target -> $source"
  else
    mkdir -p "$(dirname "$target")"
    ln -s "$source" "$target"
  fi
  linked=$((linked + 1))
}

MANAGED_MARKER="# Engineering-workflow delegate role"

# copy_one <target_path> <source_path>: install a managed copy. Replaces a
# symlink into this repo or an outdated managed copy (identified by the marker
# line); never touches any other file.
copy_one() {
  local target="$1"
  local source="$2"

  if [[ -f "$target" && ! -L "$target" ]] && cmp -s "$source" "$target"; then
    skipped=$((skipped + 1))
    return
  fi
  if [[ -L "$target" ]]; then
    local current
    current="$(readlink "$target")"
    if [[ "$current" != "$REPO_ROOT"/* ]]; then
      conflicts+=("$target (symlink -> $current)")
      return
    fi
  elif [[ -e "$target" ]] && ! head -1 "$target" | grep -qF "$MANAGED_MARKER"; then
    conflicts+=("$target (unmanaged file, not replaced)")
    return
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  would copy $source -> $target"
  else
    mkdir -p "$(dirname "$target")"
    rm -f "$target"
    cp "$source" "$target"
  fi
  linked=$((linked + 1))
}

echo "Installing personal skills from $REPO_ROOT$([[ "$DRY_RUN" -eq 1 ]] && echo ' (dry run)')"
echo

for skill_dir in "$REPO_ROOT"/*/; do
  skill_name="$(basename "$skill_dir")"
  [[ "$skill_name" == "scripts" || "$skill_name" == "commands" ]] && continue
  [[ -f "$skill_dir/SKILL.md" ]] || continue

  link_one "$CLAUDE_SKILLS/$skill_name" "$REPO_ROOT/$skill_name"
  link_one "$CODEX_SKILLS/$skill_name" "$REPO_ROOT/$skill_name"
done

for skill_path in "${MATT_SKILLS[@]}"; do
  skill_name="${skill_path##*/}"
  link_one "$CLAUDE_SKILLS/$skill_name" "$MATT_CHECKOUT/$skill_path"
  link_one "$CODEX_SKILLS/$skill_name" "$MATT_CHECKOUT/$skill_path"
done

if [[ -d "$REPO_ROOT/commands" ]]; then
  for cmd_file in "$REPO_ROOT"/commands/*.md; do
    [[ -f "$cmd_file" ]] || continue
    cmd_name="$(basename "$cmd_file")"
    link_one "$CLAUDE_COMMANDS/$cmd_name" "$cmd_file"
  done
fi

# Delegate roles (engineering-workflow registry roles). Only new files named
# after a role are created; existing personal agents are never touched.
for agent_file in "$REPO_ROOT"/agents/claude/*.md; do
  [[ -f "$agent_file" ]] || continue
  link_one "$CLAUDE_AGENTS/$(basename "$agent_file")" "$agent_file"
done
for agent_file in "$REPO_ROOT"/agents/codex/*.toml; do
  [[ -f "$agent_file" ]] || continue
  copy_one "$CODEX_AGENTS/$(basename "$agent_file")" "$agent_file"
done

echo "$([[ "$DRY_RUN" -eq 1 ]] && echo 'Would link' || echo 'Linked'):  $linked"
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

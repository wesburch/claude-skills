#!/usr/bin/env bash
# Validate that the skills and commands defined in THIS repo are correctly
# and consistently installed into Claude Code and Codex CLI.
#
# Scope: only checks names that exist in this repo (~/claude-skills). It does
# not know or care about unrelated third-party skills installed elsewhere
# (e.g. ~/.agents/skills, Claude Code plugin marketplaces) — those have their
# own install/update mechanisms and are out of scope here.
#
# Read-only: reports problems, fixes nothing. Exit 0 if clean, 1 if issues.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_SKILLS="$HOME/.claude/skills"
CODEX_SKILLS="$HOME/.codex/skills"
CLAUDE_COMMANDS="$HOME/.claude/commands"

issues=0
ok=0

pass() { echo "  [OK]   $1"; ok=$((ok + 1)); }
fail() { echo "  [FAIL] $1"; issues=$((issues + 1)); }
warn() { echo "  [WARN] $1"; }

check_link() {
  local label="$1"
  local target="$2"
  local expected_source="$3"

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    fail "$label: missing ($target)"
    return
  fi
  if [[ ! -L "$target" ]]; then
    fail "$label: exists but is a real file/directory, not a symlink ($target)"
    return
  fi
  local current
  current="$(readlink "$target")"
  if [[ "$current" != "$expected_source" ]]; then
    fail "$label: symlink points to wrong target ($current, expected $expected_source)"
    return
  fi
  if [[ ! -e "$target" ]]; then
    fail "$label: symlink is broken ($target -> $current)"
    return
  fi
  pass "$label"
}

echo "== Personal skills (source: $REPO_ROOT) =="
echo

for skill_dir in "$REPO_ROOT"/*/; do
  skill_name="$(basename "$skill_dir")"
  [[ "$skill_name" == "scripts" || "$skill_name" == "commands" ]] && continue
  [[ -f "$skill_dir/SKILL.md" ]] || continue

  echo "-- $skill_name --"
  if [[ ! -s "$skill_dir/SKILL.md" ]]; then
    fail "$skill_name/SKILL.md is empty"
  else
    pass "SKILL.md present"
  fi
  check_link "Claude skill link" "$CLAUDE_SKILLS/$skill_name" "$REPO_ROOT/$skill_name"
  check_link "Codex skill link" "$CODEX_SKILLS/$skill_name" "$REPO_ROOT/$skill_name"
  echo
done

if [[ -d "$REPO_ROOT/commands" ]]; then
  echo "== Claude slash commands (source: $REPO_ROOT/commands) =="
  echo
  for cmd_file in "$REPO_ROOT"/commands/*.md; do
    [[ -f "$cmd_file" ]] || continue
    cmd_name="$(basename "$cmd_file")"
    check_link "$cmd_name" "$CLAUDE_COMMANDS/$cmd_name" "$cmd_file"
  done
  echo
fi

echo "== Git state ($REPO_ROOT) =="
echo
if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "not a git repository"
else
  if [[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    pass "working tree clean"
  else
    fail "working tree has uncommitted changes"
    git -C "$REPO_ROOT" status --porcelain | sed 's/^/         /'
  fi

  branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  upstream="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo "")"
  if [[ -z "$upstream" ]]; then
    warn "branch '$branch' has no upstream configured"
  else
    ahead_behind="$(git -C "$REPO_ROOT" rev-list --left-right --count "$upstream...$branch" 2>/dev/null || echo "")"
    behind="$(echo "$ahead_behind" | awk '{print $1}')"
    ahead="$(echo "$ahead_behind" | awk '{print $2}')"
    if [[ "$ahead" == "0" && "$behind" == "0" ]]; then
      pass "up to date with $upstream"
    else
      fail "diverged from $upstream (ahead $ahead, behind $behind) — push/pull needed"
    fi
  fi
fi

echo
echo "$ok checks passed, $issues failed."
[[ "$issues" -eq 0 ]]

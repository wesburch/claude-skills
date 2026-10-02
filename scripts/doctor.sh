#!/usr/bin/env bash
# Validate that the skills and commands defined in THIS repo are correctly
# and consistently installed into Claude Code and Codex CLI.
#
# Scope: this repo and third-party/skills.lock. Other installations are out of
# scope except the superseded Matt plugin. Normal checks use local data only.
#
# Read-only: reports problems, fixes nothing. Exit 0 if clean, 1 if issues.
# Model-registry drift is reported as warnings and never changes the exit code;
# runtime-isolation and install errors from model-routing do.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_SKILLS="$HOME/.claude/skills"
CODEX_SKILLS="$HOME/.codex/skills"
CLAUDE_COMMANDS="$HOME/.claude/commands"

UPSTREAM=0
case "${1:-}" in
  --upstream) UPSTREAM=1 ;;
  "") ;;
  *) echo "Usage: $0 [--upstream]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "Usage: $0 [--upstream]" >&2; exit 2; }
source "$REPO_ROOT/scripts/third-party.sh"
load_third_party || exit 1

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

# check_copy <label> <target> <source>: a real file identical to the source.
check_copy() {
  local label="$1"
  local target="$2"
  local expected_source="$3"

  if [[ -L "$target" ]]; then
    fail "$label: is a symlink; Codex cannot load symlinked agents (rerun install.sh)"
  elif [[ ! -f "$target" ]]; then
    fail "$label: missing ($target)"
  elif ! cmp -s "$target" "$expected_source"; then
    fail "$label: installed copy differs from $expected_source (rerun install.sh)"
  else
    pass "$label (copy in sync)"
  fi
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

if [[ -d "$REPO_ROOT/agents" ]]; then
  echo "== Delegate roles (source: $REPO_ROOT/agents) =="
  echo
  for agent_file in "$REPO_ROOT"/agents/claude/*.md; do
    [[ -f "$agent_file" ]] || continue
    check_link "Claude $(basename "$agent_file")" "$HOME/.claude/agents/$(basename "$agent_file")" "$agent_file"
  done
  for agent_file in "$REPO_ROOT"/agents/codex/*.toml; do
    [[ -f "$agent_file" ]] || continue
    check_copy "Codex $(basename "$agent_file")" "$HOME/.codex/agents/$(basename "$agent_file")" "$agent_file"
  done
  echo
fi

echo "== Pinned Matt Pocock skills =="
if [[ -d "$MATT_CHECKOUT" ]]; then
  pass "checkout exists"
  if validate_matt_checkout; then pass "checkout origin and clean tree"; else fail "checkout validation"; fi
  if [[ "$(git -C "$MATT_CHECKOUT" rev-parse HEAD 2>/dev/null)" == "$MATT_PIN" ]]; then
    pass "checkout at lock pin $MATT_PIN"
  else
    fail "checkout is not at lock pin $MATT_PIN"
  fi
else
  fail "checkout missing: $MATT_CHECKOUT"
fi
if [[ -s "$MATT_CHECKOUT/LICENSE" ]]; then pass "upstream license present"; else fail "upstream license missing"; fi
for skill_path in "${MATT_SKILLS[@]}"; do
  skill_name="${skill_path##*/}"
  if [[ -s "$MATT_CHECKOUT/$skill_path/SKILL.md" ]]; then pass "$skill_name source"; else fail "$skill_name source missing"; fi
  check_link "Claude $skill_name" "$CLAUDE_SKILLS/$skill_name" "$MATT_CHECKOUT/$skill_path"
  check_link "Codex $skill_name" "$CODEX_SKILLS/$skill_name" "$MATT_CHECKOUT/$skill_path"
done
if check_matt_plugin; then pass "superseded Matt plugin disabled"; else fail "superseded Matt plugin enabled or settings unreadable"; fi
if [[ "$UPSTREAM" -eq 1 ]]; then
  if upstream_head="$(git ls-remote "$MATT_SOURCE" HEAD)"; then
    pass "upstream reachable: $upstream_head (informational; lock unchanged)"
  else
    fail "explicit upstream check could not reach source"
  fi
fi
echo

ROUTING="$REPO_ROOT/engineering-workflow/scripts/model-routing"
if [[ -x "$ROUTING" ]]; then
  echo "== Model registry and runtime isolation (registry drift warns; isolation errors fail) =="
  echo
  "$ROUTING" check > "${TMPDIR:-/tmp}/doctor-routing.$$" 2>&1
  routing_status=$?
  sed 's/^/  /' "${TMPDIR:-/tmp}/doctor-routing.$$"
  rm -f "${TMPDIR:-/tmp}/doctor-routing.$$"
  if [[ "$routing_status" -eq 0 ]]; then
    pass "model-routing check: no runtime-isolation or install errors"
  else
    fail "model-routing check reported runtime-isolation or install errors (exit $routing_status)"
  fi
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

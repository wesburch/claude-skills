#!/usr/bin/env bash
# Shared lock reader and read-only checkout checks for install.sh and doctor.sh.

load_third_party() {
  MATT_CHECKOUT="$HOME/.local/share/claude-skills/third-party/mattpocock-skills"
  MATT_SOURCE="" MATT_PIN=""
  MATT_SKILLS=()
  local key value extra
  while read -r key value extra; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    [[ -z "$extra" ]] || { echo "Invalid skills.lock record" >&2; return 1; }
    case "$key" in
      source) [[ -z "$MATT_SOURCE" ]] || return 1; MATT_SOURCE="$value" ;;
      commit) [[ -z "$MATT_PIN" ]] || return 1; MATT_PIN="$value" ;;
      skill)
        [[ "$value" =~ ^skills/[a-z-]+/[a-z-]+$ ]] || return 1
        local prior
        for prior in ${MATT_SKILLS[@]+"${MATT_SKILLS[@]}"}; do
          [[ "${prior##*/}" != "${value##*/}" ]] || return 1
        done
        MATT_SKILLS+=("$value") ;;
      *) echo "Unknown skills.lock key: $key" >&2; return 1 ;;
    esac
  done < "$REPO_ROOT/third-party/skills.lock"
  [[ "$MATT_SOURCE" == https://github.com/mattpocock/skills.git &&
     "$MATT_PIN" =~ ^[a-f0-9]{40}$ && ${#MATT_SKILLS[@]} -eq 5 ]] || {
    echo "Invalid third-party lock (expected source, full pin and five skills)" >&2
    return 1
  }
}

# Refuse unmanaged paths, nested repositories, alternate origins and dirty trees.
# Never stash, clean, reset, move or edit third-party content.
validate_matt_checkout() {
  [[ -d "$MATT_CHECKOUT/.git" && ! -L "$MATT_CHECKOUT" ]] || {
    echo "Not a standalone checkout: $MATT_CHECKOUT" >&2; return 1;
  }
  local origin changes top
  top="$(git -C "$MATT_CHECKOUT" rev-parse --show-toplevel)" || return 1
  [[ "$top" == "$(cd "$MATT_CHECKOUT" && pwd -P)" ]] || return 1
  origin="$(git -C "$MATT_CHECKOUT" remote get-url origin)" || return 1
  [[ "$origin" == "$MATT_SOURCE" ]] || {
    echo "Unexpected third-party origin: $origin" >&2; return 1;
  }
  changes="$(git -C "$MATT_CHECKOUT" status --porcelain --untracked-files=all --ignored)" || return 1
  [[ -z "$changes" ]] || {
    echo "Dirty third-party checkout; left untouched: $MATT_CHECKOUT" >&2; return 1;
  }
}

prepare_matt_checkout() {
  local head
  if [[ -e "$MATT_CHECKOUT" || -L "$MATT_CHECKOUT" ]]; then
    validate_matt_checkout || return 1
    head="$(git -C "$MATT_CHECKOUT" rev-parse HEAD)" || return 1
    if [[ "$head" != "$MATT_PIN" ]]; then
      if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  would fetch pin if missing and checkout --detach $MATT_PIN in $MATT_CHECKOUT"
        return
      fi
      if ! git -C "$MATT_CHECKOUT" cat-file -e "$MATT_PIN^{commit}" 2>/dev/null; then
        git -C "$MATT_CHECKOUT" fetch origin "$MATT_PIN" || return 1
      fi
      git -C "$MATT_CHECKOUT" checkout --detach "$MATT_PIN" || return 1
    fi
  else
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "  would clone $MATT_SOURCE into $MATT_CHECKOUT and checkout --detach $MATT_PIN"
      return
    fi
    mkdir -p "$(dirname "$MATT_CHECKOUT")"
    git clone --no-checkout "$MATT_SOURCE" "$MATT_CHECKOUT" || return 1
    if ! git -C "$MATT_CHECKOUT" cat-file -e "$MATT_PIN^{commit}" 2>/dev/null; then
      git -C "$MATT_CHECKOUT" fetch origin "$MATT_PIN" || return 1
    fi
    git -C "$MATT_CHECKOUT" checkout --detach "$MATT_PIN" || return 1
  fi
  validate_matt_checkout || return 1
  [[ -s "$MATT_CHECKOUT/LICENSE" ]] || { echo "Third-party LICENSE missing" >&2; return 1; }
  local path
  for path in "${MATT_SKILLS[@]}"; do
    [[ -s "$MATT_CHECKOUT/$path/SKILL.md" ]] || {
      echo "Missing pinned skill: $path/SKILL.md" >&2; return 1;
    }
  done
}

# Settings are local data. Do not invoke a model or refresh plugin marketplaces.
# User settings < project settings < local settings < managed settings.
check_matt_plugin() {
  ruby -rjson -e '
    key = "mattpocock-skills@claude-plugins-official"
    enabled = false
    ARGV.each do |path|
      next unless File.exist?(path)
      config = JSON.parse(File.read(path))
      plugins = config.fetch("enabledPlugins", {})
      enabled = plugins[key] if plugins.key?(key)
    end
    if enabled
      warn "#{key} still enabled; run: claude plugin disable #{key} --scope user"
      exit 1
    end
  ' "$HOME/.claude/settings.json" "$REPO_ROOT/.claude/settings.json" \
    "$REPO_ROOT/.claude/settings.local.json" \
    "/Library/Application Support/ClaudeCode/managed-settings.json"
}

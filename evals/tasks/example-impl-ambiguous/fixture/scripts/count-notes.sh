#!/usr/bin/env bash
# Print how many notes (*.md) a directory holds.
set -euo pipefail

if [[ $# -ne 1 || ! -d "$1" ]]; then
  echo "usage: scripts/count-notes.sh DIR" >&2
  exit 1
fi
find "$1" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' '

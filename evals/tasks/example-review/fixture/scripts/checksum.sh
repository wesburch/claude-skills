#!/usr/bin/env bash
# Print the SHA-256 of one file.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: scripts/checksum.sh FILE" >&2
  exit 1
fi
shasum -a 256 "$1" | cut -d' ' -f1

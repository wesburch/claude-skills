#!/usr/bin/env bash
# Rotate a log file: FILE becomes FILE.1, FILE.1 becomes FILE.2, and so on.
set -euo pipefail

keep=3

usage() {
  echo "usage: scripts/rotate-log.sh [--keep N] FILE"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --keep)
      keep="$2"
      shift 2
      ;;
    *)
      file="$1"
      shift
      ;;
  esac
done

# Start from a file that exists.
touch $file

i=$keep
while [[ $i -gt 1 ]]; do
  prev=$((i - 1))
  if [[ -e "$file.$prev" ]]; then
    mv "$file.$prev" "$file.$i"
  fi
  i=$prev
done

mv "$file" "$file.1"
: > "$file"
echo "rotated $file"

#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shell_files=()

while IFS= read -r shell_file; do
  shell_files+=("$shell_file")
done < <(find "$ROOT_DIR/scripts" "$ROOT_DIR/tests" -name '*.sh' | sort)
shell_files+=("$ROOT_DIR/bin/midflight")

if command -v shellcheck >/dev/null 2>&1; then
  echo "==> shellcheck"
  shellcheck -x -s bash -e SC1091 "${shell_files[@]}"
else
  echo "==> shellcheck (skipped: shellcheck not installed)"
fi

for test_script in "$ROOT_DIR"/tests/query_*.sh "$ROOT_DIR"/tests/cli_*.sh; do
  [ -e "$test_script" ] || continue
  echo "==> $(basename "$test_script")"
  bash "$test_script"
done

echo "PASS: all MidFlight shell tests passed"

#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for test_script in "$ROOT_DIR"/tests/query_*.sh; do
  echo "==> $(basename "$test_script")"
  bash "$test_script"
done

echo "PASS: all MidFlight shell tests passed"

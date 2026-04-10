#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=codex
EOF

cat > "$TEST_DIR/bin/codex" <<'EOF'
#!/bin/bash

set -euo pipefail

output_file=""

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output-last-message)
      output_file="$2"
      shift 2
      ;;
    --model|-c)
      shift 2
      ;;
    --full-auto|--skip-git-repo-check)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

: > "$output_file"
EOF

chmod +x "$TEST_DIR/bin/codex"

QUERY_FILE="$(
  write_query_file <<'EOF'
## Context
We are testing error handling.

## Question
What happens on an empty response?
EOF
)"

set +e
output="$(run_query "$QUERY_FILE" consult 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: query.sh should fail on an empty provider response" >&2
  exit 1
fi

assert_contains "$output" "Error: codex returned an empty response." "empty response should produce a helpful error"

echo "PASS: empty provider responses fail with a clear error"

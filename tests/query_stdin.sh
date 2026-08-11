#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=codex
codex_model=test-model
codex_reasoning_effort=high
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
    --model|-c|--sandbox)
      shift 2
      ;;
    --skip-git-repo-check)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

cat > /dev/null

if [ -z "$output_file" ]; then
  echo "stub codex: missing output file" >&2
  exit 1
fi

printf 'stdin-detached\n' > "$output_file"
EOF

chmod +x "$TEST_DIR/bin/codex"

QUERY_FILE="$(
  write_query_file <<'EOF'
## Context
Testing stdin detachment.

## Question
Does the wrapper return promptly?
EOF
)"

STDIN_PIPE="$TEST_DIR/stdin.pipe"
mkfifo "$STDIN_PIPE"

( sleep 3 > "$STDIN_PIPE" ) &
writer_pid=$!

SECONDS=0
output="$(run_query "$QUERY_FILE" consult < "$STDIN_PIPE")"
duration=$SECONDS

wait "$writer_pid" || true

if [ "$duration" -ge 2 ]; then
  echo "FAIL: query.sh took ${duration}s; provider stdin was likely not detached" >&2
  exit 1
fi

assert_eq "stdin-detached" "$output" "stdin detachment test should return the stubbed output"

echo "PASS: provider stdin detached in ${duration}s"

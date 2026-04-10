#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/midflight-test.XXXXXX")"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/home/.config/mid-flight"

cat > "$TEST_DIR/home/.config/mid-flight/config" <<'EOF'
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

cat > /dev/null

if [ -z "$output_file" ]; then
  echo "stub codex: missing output file" >&2
  exit 1
fi

printf 'stdin-detached\n' > "$output_file"
EOF

chmod +x "$TEST_DIR/bin/codex"

QUERY_FILE="$TEST_DIR/query.md"
cat > "$QUERY_FILE" <<'EOF'
## Context
Testing stdin detachment.

## Question
Does the wrapper return promptly?
EOF

STDIN_PIPE="$TEST_DIR/stdin.pipe"
mkfifo "$STDIN_PIPE"

( sleep 3 > "$STDIN_PIPE" ) &
writer_pid=$!

SECONDS=0
output="$(
  HOME="$TEST_DIR/home" \
  PATH="$TEST_DIR/bin:$PATH" \
  bash "$ROOT_DIR/scripts/query.sh" "$QUERY_FILE" consult < "$STDIN_PIPE"
)"
duration=$SECONDS

wait "$writer_pid" || true

if [ "$duration" -ge 2 ]; then
  echo "FAIL: query.sh took ${duration}s; provider stdin was likely not detached" >&2
  exit 1
fi

if [ "$output" != "stdin-detached" ]; then
  echo "FAIL: unexpected output: $output" >&2
  exit 1
fi

echo "PASS: provider stdin detached in ${duration}s"

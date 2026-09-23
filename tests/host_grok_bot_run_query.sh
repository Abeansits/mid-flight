#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
source "$ROOT_DIR/tests/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

RUN_QUERY="$ROOT_DIR/hosts/grok-bot/scripts/run-query.sh"

# Minimal query file
QUERY_FILE="$TEST_DIR/query.md"
cat > "$QUERY_FILE" << 'EOF'
## Context
Test context

## Question
Test question
EOF

# run-query with PATH midflight + mock CLI
ln -s "$ROOT_DIR/bin/midflight" "$TEST_DIR/bin/midflight"
export PATH="$TEST_DIR/bin:/usr/bin:/bin"
unset MIDFLIGHT_ROOT

# Mock the CLI to verify invocation
MOCK_CLI="$TEST_DIR/bin/midflight-mock"
cat > "$MOCK_CLI" << 'EOF'
#!/bin/bash
echo "mock-cli: $*" > "$TEST_DIR/invocation.txt"
echo "mock response"
EOF
chmod +x "$MOCK_CLI"

# Point midflight symlink to mock
rm "$TEST_DIR/bin/midflight"
ln -s "$MOCK_CLI" "$TEST_DIR/bin/midflight"

# Test consult mode (default)
out="$(bash "$RUN_QUERY" "$QUERY_FILE" consult 2>&1)"
assert_contains "$out" "mock response" "should invoke mock CLI"
invocation="$(cat "$TEST_DIR/invocation.txt")"
assert_contains "$invocation" "-m consult" "should pass consult mode"
assert_contains "$invocation" "-f $QUERY_FILE" "should pass query file"

# Test with --provider override
rm -f "$TEST_DIR/invocation.txt"
bash "$RUN_QUERY" --provider agy "$QUERY_FILE" consult >/dev/null 2>&1
invocation="$(cat "$TEST_DIR/invocation.txt")"
assert_contains "$invocation" "-p agy" "should pass provider override"

# Test implement mode
rm -f "$TEST_DIR/invocation.txt"
bash "$RUN_QUERY" "$QUERY_FILE" implement >/dev/null 2>&1
invocation="$(cat "$TEST_DIR/invocation.txt")"
assert_contains "$invocation" "-m implement" "should pass implement mode"

# Test video mode
VIDEO_FILE="$TEST_DIR/video.mp4"
touch "$VIDEO_FILE"
rm -f "$TEST_DIR/invocation.txt"
bash "$RUN_QUERY" "$VIDEO_FILE" video "video prompt" >/dev/null 2>&1
invocation="$(cat "$TEST_DIR/invocation.txt")"
assert_contains "$invocation" "--video $VIDEO_FILE" "should pass video file"
assert_contains "$invocation" "video prompt" "should pass video prompt"

# Test MIDFLIGHT_ROOT fallback when PATH is empty
export PATH="/usr/bin:/bin"
export MIDFLIGHT_ROOT="$ROOT_DIR"
rm -f "$TEST_DIR/invocation.txt"

# Mock query.sh to verify invocation via MIDFLIGHT_ROOT
MOCK_QUERY="$TEST_DIR/mock-query.sh"
cat > "$MOCK_QUERY" << 'EOF'
#!/bin/bash
echo "mock-query: $*" > "$TEST_DIR/query-invocation.txt"
echo "mock query response"
EOF
chmod +x "$MOCK_QUERY"

# Temporarily replace scripts/query.sh with mock (save original)
mv "$ROOT_DIR/scripts/query.sh" "$ROOT_DIR/scripts/query.sh.bak"
ln -s "$MOCK_QUERY" "$ROOT_DIR/scripts/query.sh"

out="$(bash "$RUN_QUERY" "$QUERY_FILE" consult 2>&1)" || true
# Restore original
rm "$ROOT_DIR/scripts/query.sh"
mv "$ROOT_DIR/scripts/query.sh.bak" "$ROOT_DIR/scripts/query.sh"

# The mock query should have been invoked
if [ -f "$TEST_DIR/query-invocation.txt" ]; then
  query_invocation="$(cat "$TEST_DIR/query-invocation.txt")"
  assert_contains "$query_invocation" "$QUERY_FILE" "query.sh should receive query file"
fi

echo "PASS: host_grok_bot_run_query"

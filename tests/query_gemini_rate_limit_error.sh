#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=gemini
EOF

cat > "$TEST_DIR/bin/gemini" <<'EOF'
#!/bin/bash

set -euo pipefail

echo "429 rate limit exceeded" >&2
exit 1
EOF

chmod +x "$TEST_DIR/bin/gemini"

QUERY_FILE="$(
  write_query_file <<'EOF'
## Context
We are testing provider rate limits.

## Question
Can MidFlight surface a better error?
EOF
)"

set +e
output="$(run_query "$QUERY_FILE" consult 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: query.sh should fail when Gemini is rate limited" >&2
  exit 1
fi

assert_contains "$output" "Error: Gemini hit a rate limit or quota." "rate limits should be classified clearly"
assert_contains "$output" "429 rate limit exceeded" "rate limits should preserve the provider detail"

echo "PASS: provider rate limits are surfaced with a specific error"

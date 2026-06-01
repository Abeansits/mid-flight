#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

# Invalid mode is rejected before any provider work.
set +e
bad_mode="$(run_cli -m bogus "a question" 2>&1)"
bad_status=$?
set -e
assert_eq "2" "$bad_status" "invalid mode should exit 2"
assert_contains "$bad_mode" "invalid mode 'bogus'" "invalid mode should name the bad value"

# No question and no input source is a usage error.
set +e
no_input="$(run_cli 2>&1)"
no_status=$?
set -e
assert_eq "2" "$no_status" "missing question should exit 2"
assert_contains "$no_input" "no question provided" "missing question should be explained"

# Unknown option is rejected.
set +e
bad_opt="$(run_cli --bogus 2>&1)"
opt_status=$?
set -e
assert_eq "2" "$opt_status" "unknown option should exit 2"
assert_contains "$bad_opt" "unknown option: --bogus" "unknown option should be named"

echo "PASS: argument validation rejects bad mode, missing input, and unknown options"

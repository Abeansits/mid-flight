#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'CFG'
provider=codex
codex_model=test-model
gemini_model=test-gemini
CFG

write_codex_stub "codex says use SSE"
write_gemini_stub "gemini says use WebSockets"
write_agy_stub "agy says use WebSockets"
write_grok_stub "grok agrees with SSE"

# Primary UX: --dual SECONDARY (primary from config)
output="$(run_cli --dual gemini "SSE or WebSockets?")"
assert_contains "$output" "## Provider A: Codex" "--dual should label primary from config"
assert_contains "$output" "## Provider B: Gemini" "--dual should label secondary"
assert_contains "$output" "codex says use SSE" "--dual should print primary answer"
assert_contains "$output" "gemini says use WebSockets" "--dual should print secondary answer"
assert_contains "$output" "## Where they differ" "--dual should include disagreement framing"
assert_contains "$output" "Both answers are printed above" "differing answers get honest compare hint"
assert_contains "$output" "does not invent a disagreement analysis" "no fake LLM diff"

# Explicit form: --providers A,B
output="$(run_cli --providers codex,agy "SSE or WebSockets?")"
assert_contains "$output" "## Provider A: Codex" "--providers should label A"
assert_contains "$output" "## Provider B: Antigravity" "--providers should label B (agy display)"
assert_contains "$output" "agy says use WebSockets" "--providers should print B answer"

# -p + --dual
output="$(run_cli -p grok --dual agy "tradeoffs?")"
assert_contains "$output" "## Provider A: Grok" "-p should become Provider A with --dual"
assert_contains "$output" "## Provider B: Antigravity" "--dual secondary is B"
assert_contains "$output" "grok agrees with SSE" "primary answer present"
assert_contains "$output" "agy says use WebSockets" "secondary answer present"

# Identical responses → structural identical note
write_codex_stub "same answer"
write_gemini_stub "same answer"
output="$(run_cli --providers codex,gemini "same?")"
assert_contains "$output" "Responses are identical" "identical stubs get identical note"

# One failure: still show the successful answer + error for failed
cat > "$TEST_DIR/bin/gemini" <<'STUB'
#!/bin/bash
echo "Error: Gemini authentication failed. Re-authenticate the Gemini CLI and try again." >&2
echo "Error: Gemini authentication failed. Re-authenticate the Gemini CLI and try again."
exit 1
STUB
chmod +x "$TEST_DIR/bin/gemini"
write_codex_stub "codex survived"

set +e
output="$(run_cli --providers codex,gemini "partial?" 2>/dev/null)"
status=$?
set -e
assert_eq "1" "$status" "one-sided dual failure should exit 1"
assert_contains "$output" "## Provider A: Codex" "successful provider still labeled"
assert_contains "$output" "codex survived" "successful answer still shown"
assert_contains "$output" "## Provider B: Gemini" "failed provider still labeled"
assert_contains "$output" "Gemini authentication failed" "failed provider error shown"
assert_contains "$output" "Gemini failed; only Codex" "framing notes which side failed"

# Refuse implement dual
set +e
bad="$(run_cli -m implement --dual agy "do it" 2>&1)"
bad_status=$?
set -e
assert_eq "2" "$bad_status" "implement+dual should exit 2"
assert_contains "$bad" "consult-only" "implement dual should explain consult-only"

# Refuse video dual
set +e
bad="$(run_cli --video ./nope.mp4 --dual agy "x" 2>&1)"
bad_status=$?
set -e
assert_eq "2" "$bad_status" "video+dual should exit 2"
assert_contains "$bad" "dual-consult" "video dual should mention dual-consult"

# Refuse same provider twice
set +e
bad="$(run_cli --providers codex,codex "x" 2>&1)"
bad_status=$?
set -e
assert_eq "2" "$bad_status" "same provider twice should exit 2"
assert_contains "$bad" "two different providers" "same-provider error should be clear"

# Refuse --dual and --providers together
set +e
bad="$(run_cli --dual agy --providers codex,agy "x" 2>&1)"
bad_status=$?
set -e
assert_eq "2" "$bad_status" "dual+providers should exit 2"
assert_contains "$bad" "either --dual or --providers" "mutual exclusion message"

# Refuse --model with dual
set +e
bad="$(run_cli --dual agy --model gpt-5 "x" 2>&1)"
bad_status=$?
set -e
assert_eq "2" "$bad_status" "model+dual should exit 2"
assert_contains "$bad" "--model cannot be combined with dual-consult" "model dual refusal"

# Alias normalization: antigravity → agy
write_codex_stub "a"
write_agy_stub "b"
output="$(run_cli --providers codex,antigravity "alias?")"
assert_contains "$output" "## Provider B: Antigravity" "antigravity alias normalizes for display"

echo "PASS: dual-consult CLI (--dual / --providers) prints both answers and frames disagreement"

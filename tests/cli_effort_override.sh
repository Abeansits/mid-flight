#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

stdout_file="$TEST_DIR/stdout.txt"
stderr_file="$TEST_DIR/stderr.txt"

# 1. -p agy --model M --effort high records --model M --effort high.
write_config <<'CFG'
provider=codex
codex_model=gpt-6-sol
CFG
write_agy_stub "agy-effort-ok"

out="$(run_cli -p agy --model M --effort high "Check agy effort")"
assert_eq "agy-effort-ok" "$out" "-p agy --model M --effort high should succeed"
assert_eq "M" "$(cat "$TEST_DIR/agy_model.txt")" "agy should receive --model M"
assert_eq "high" "$(cat "$TEST_DIR/agy_effort.txt")" "agy should receive --effort high"
assert_eq "provider=codex" "$(grep '^provider=' "$HOME/.config/mid-flight/config")" \
  "real config must remain untouched"

# 2. --effort without -p overrides the configured provider's effort key.
write_config <<'CFG'
provider=agy
agy_effort=low
CFG
out="$(run_cli --effort medium "Override configured agy effort")"
assert_eq "agy-effort-ok" "$out" "--effort without -p should succeed for agy"
assert_eq "medium" "$(cat "$TEST_DIR/agy_effort.txt")" "agy should receive overridden effort"
assert_eq "agy_effort=low" "$(grep '^agy_effort=' "$HOME/.config/mid-flight/config")" \
  "real agy_effort in config must remain untouched"

# 3. -p codex --effort xhigh writes codex_reasoning_effort.
cat > "$TEST_DIR/bin/codex" <<EOF
#!/bin/bash
set -euo pipefail
output_file=""
reasoning=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o|--output-last-message) output_file="\$2"; shift 2 ;;
    -c) reasoning="\$2"; shift 2 ;;
    --model|--sandbox) shift 2 ;;
    --skip-git-repo-check) shift ;;
    *) shift ;;
  esac
done
printf '%s' "\$reasoning" > "$TEST_DIR/codex_reasoning.txt"
printf 'codex-effort-ok\n' > "\$output_file"
EOF
chmod +x "$TEST_DIR/bin/codex"

out="$(run_cli -p codex --effort xhigh "Check codex effort")"
assert_eq "codex-effort-ok" "$out" "-p codex --effort xhigh should succeed"
assert_eq 'model_reasoning_effort="xhigh"' "$(cat "$TEST_DIR/codex_reasoning.txt")" \
  "codex should receive model_reasoning_effort=\"xhigh\""

# 4. -p grok --effort low writes grok_effort.
write_grok_stub "grok-effort-ok"
out="$(run_cli -p grok --effort low "Check grok effort")"
assert_eq "grok-effort-ok" "$out" "-p grok --effort low should succeed"
assert_eq "low" "$(cat "$TEST_DIR/grok_effort.txt")" "grok should receive --effort low"

# 5. Providers without an effort key exit 2 with midflight: on stderr and empty stdout.
write_gemini_stub "should-not-run"
write_claude_stub "should-not-run"
for no_effort_provider in gemini opencode oz claude; do
  set +e
  run_cli -p "$no_effort_provider" --effort high "Unsupported effort" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  assert_eq "2" "$status" "--effort with $no_effort_provider should exit 2"
  assert_eq "" "$(cat "$stdout_file")" "--effort with $no_effort_provider should print empty stdout"
  assert_contains "$(cat "$stderr_file")" "midflight:" "--effort with $no_effort_provider should print midflight: on stderr"
done

# 6. Configured provider without an effort key (no -p) also exits 2 cleanly.
write_config <<'CFG'
provider=claude
CFG
set +e
run_cli --effort high "Configured claude without -p" >"$stdout_file" 2>"$stderr_file"
status=$?
set -e
assert_eq "2" "$status" "--effort with configured claude should exit 2"
assert_eq "" "$(cat "$stdout_file")" "--effort with configured claude should print empty stdout"
assert_contains "$(cat "$stderr_file")" "midflight:" "--effort with configured claude should print midflight: on stderr"

# 7. --effort combined with dual-consult exits 2.
set +e
run_cli --dual agy --effort high "Dual with effort" >"$stdout_file" 2>"$stderr_file"
status=$?
set -e
assert_eq "2" "$status" "--dual with --effort should exit 2"
assert_eq "" "$(cat "$stdout_file")" "--dual with --effort should print empty stdout"
assert_contains "$(cat "$stderr_file")" "midflight:" "--dual with --effort should print midflight: on stderr"

echo "PASS: --effort maps to provider effort keys and rejects unsupported providers/dual"

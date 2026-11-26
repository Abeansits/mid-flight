#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

# Simulate signed-in agy account state that depends on seeing the real $HOME
# (not a symlinked temp HOME overlay).
mkdir -p "$HOME/.antigravity"
printf 'signed-in-account\n' > "$HOME/.antigravity/account"

cat > "$TEST_DIR/bin/agy" <<EOF
#!/bin/bash
set -euo pipefail
model=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    --model) model="\$2"; shift 2 ;;
    -p|--print|--prompt|--effort|--add-dir|--output-format) shift 2 ;;
    --dangerously-skip-permissions) shift ;;
    *) shift ;;
  esac
done
printf '%s' "\$HOME" > "$TEST_DIR/seen_home.txt"
printf '%s' "\$model" > "$TEST_DIR/seen_model.txt"
# Fail if HOME or its .antigravity/account entry is a symlink overlay.
if [ -L "\$HOME" ] || [ -L "\$HOME/.antigravity" ] || [ ! -f "\$HOME/.antigravity/account" ]; then
  echo "error: invalid model selection (--model \"\$model\"): not recognized under symlinked HOME" >&2
  exit 1
fi
printf 'agy-account-ok\n'
EOF
chmod +x "$TEST_DIR/bin/agy"

# Real config points at codex and must remain untouched across all overrides.
write_config <<'CFG'
provider=codex
codex_model=gpt-6-sol
CFG
expected_config="$(cat "$HOME/.config/mid-flight/config")"

# 1. -p agy --model <account-only-model> keeps real HOME.
out="$(run_cli -p agy --model gemini-4-hydrogen-high "Check account visibility")"
assert_eq "agy-account-ok" "$out" "-p agy --model should succeed with real HOME"
assert_eq "$HOME" "$(cat "$TEST_DIR/seen_home.txt")" "agy must see real HOME under -p and --model"
assert_eq "gemini-4-hydrogen-high" "$(cat "$TEST_DIR/seen_model.txt")" "agy must receive --model override"
assert_eq "$expected_config" "$(cat "$HOME/.config/mid-flight/config")" "real config must remain untouched"

# 2. --model alone with provider=agy in config keeps real HOME.
write_config <<'CFG'
provider=agy
agy_model=default-model
CFG
expected_config="$(cat "$HOME/.config/mid-flight/config")"
out="$(run_cli --model gemini-4-hydrogen-high "Check configured agy with --model")"
assert_eq "agy-account-ok" "$out" "--model with provider=agy should succeed"
assert_eq "$HOME" "$(cat "$TEST_DIR/seen_home.txt")" "agy must see real HOME under --model"
assert_eq "gemini-4-hydrogen-high" "$(cat "$TEST_DIR/seen_model.txt")" "agy must receive --model override"
assert_eq "$expected_config" "$(cat "$HOME/.config/mid-flight/config")" "real config must remain untouched"

# 3. -c <alt-config> keeps real HOME.
alt_config="$TEST_DIR/alt.config"
cat > "$alt_config" <<'CFG'
provider=agy
agy_model=alt-account-model
CFG
out="$(run_cli -c "$alt_config" "Check -c alt config")"
assert_eq "agy-account-ok" "$out" "-c config should succeed"
assert_eq "$HOME" "$(cat "$TEST_DIR/seen_home.txt")" "agy must see real HOME under -c"
assert_eq "alt-account-model" "$(cat "$TEST_DIR/seen_model.txt")" "agy must receive model from -c config"

# 4. --dual keeps real HOME.
write_codex_stub "codex-dual-ok"
out="$(run_cli --providers codex,agy "Dual home check")"
assert_contains "$out" "agy-account-ok" "dual-consult agy side should succeed"
assert_eq "$HOME" "$(cat "$TEST_DIR/seen_home.txt")" "agy must see real HOME in dual-consult"

# 5. --model without provider= in config (or missing config) does not crash under set -e.
: > "$HOME/.config/mid-flight/config"
write_codex_stub "codex-default-ok"
out="$(run_cli --model custom-codex-model "Missing provider line check")"
assert_eq "codex-default-ok" "$out" "--model without provider= in config should default to codex"

rm -f "$HOME/.config/mid-flight/config"
out="$(run_cli --model custom-codex-model "Missing config file check")"
assert_eq "codex-default-ok" "$out" "--model without config file should default to codex"

echo "PASS: agy sees real HOME under -p, --model, -c, and --dual"

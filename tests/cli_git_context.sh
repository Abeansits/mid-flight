#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOFCONFIG'
provider=codex
codex_model=test-model
EOFCONFIG

write_codex_stub "git-ok"

# --- not a git repo ---
mkdir -p "$TEST_DIR/not-a-repo"
pushd "$TEST_DIR/not-a-repo" >/dev/null
set +e
err_status="$(run_cli --git-status "anything?" 2>&1)"
ec_status=$?
err_diff="$(run_cli --diff "anything?" 2>&1)"
ec_diff=$?
set -e
popd >/dev/null
assert_eq "2" "$ec_status" "outside a git repo --git-status should exit 2"
assert_contains "$err_status" "not a git repository" "should explain missing work tree"
assert_eq "2" "$ec_diff" "outside a git repo --diff should exit 2"
assert_contains "$err_diff" "not a git repository" "should explain missing work tree for --diff"

echo "PASS: not-a-repo fails clearly for --git-status and --diff"

# --- fixture repo ---
REPO="$TEST_DIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "midflight-test@example.com"
git -C "$REPO" config user.name "MidFlight Test"
printf 'line one\n' > "$REPO/app.txt"
git -C "$REPO" add app.txt
git -C "$REPO" commit -q -m "initial"
git -C "$REPO" checkout -q -b feature/git-context
printf 'line one\nline two unstaged\n' > "$REPO/app.txt"
printf 'staged only\n' > "$REPO/staged.txt"
git -C "$REPO" add staged.txt
printf 'Human notes for the consult.\n' > "$TEST_DIR/notes.md"

write_codex_stub "git-happy"
pushd "$REPO" >/dev/null
output="$(run_cli --git-status --diff --context "$TEST_DIR/notes.md" \
  "does this change look right?")"
popd >/dev/null
assert_eq "git-happy" "$output" "git context happy path should return stub"

prompt="$(cat "$TEST_DIR/codex_prompt.txt")"
assert_contains "$prompt" "## Context" "should assemble a Context section"
assert_contains "$prompt" "Human notes for the consult." "should keep --context prose"
assert_contains "$prompt" "### git branch" "should label git branch"
assert_contains "$prompt" "feature/git-context" "should include current branch"
assert_contains "$prompt" "### git status" "should label git status"
assert_contains "$prompt" "staged.txt" "status should mention staged file"
assert_contains "$prompt" "### git diff (working tree)" "should label working-tree diff"
assert_contains "$prompt" "line two unstaged" "working-tree diff should include unstaged edit"
assert_contains "$prompt" "### git diff --cached (staged)" "should label staged diff"
assert_contains "$prompt" "staged only" "staged diff should include staged.txt contents"
assert_contains "$prompt" "does this change look right?" "should include the question"

echo "PASS: --git-status/--diff happy path + combine with --context"

# --- git missing from PATH ---
# Build a PATH that has the provider stub + common utils, but no `git`.
NOGIT="$TEST_DIR/nogit-path"
mkdir -p "$NOGIT"
for cmd in bash head wc tr mktemp cat rm mkdir cp ln mv sed grep cut chmod dirname basename uname readlink pwd; do
  src="$(command -v "$cmd" || true)"
  if [ -n "$src" ] && [ -x "$src" ]; then
    ln -sf "$src" "$NOGIT/$cmd"
  fi
done
write_codex_stub "should-not-run"
pushd "$REPO" >/dev/null
set +e
err="$(PATH="$TEST_DIR/bin:$NOGIT" run_cli --git-status "x?" 2>&1)"
ec=$?
set -e
popd >/dev/null
assert_eq "2" "$ec" "missing git should exit 2"
assert_contains "$err" "git is required" "should explain missing git binary"

echo "PASS: missing git fails clearly"

# --- truncation ---
python3 - <<PY
from pathlib import Path
p = Path("$REPO/app.txt")
p.write_text("line one\n" + ("x" * 5000) + "\n")
PY
write_codex_stub "git-trunc"
pushd "$REPO" >/dev/null
output="$(MIDFLIGHT_GIT_CONTEXT_MAX_BYTES=200 run_cli --diff "too big?")"
popd >/dev/null
assert_eq "git-trunc" "$output" "truncation path should still succeed"
prompt="$(cat "$TEST_DIR/codex_prompt.txt")"
assert_contains "$prompt" "[midflight: truncated git diff (working tree) at 200 bytes" \
  "should include truncation marker"
assert_contains "$prompt" "MIDFLIGHT_GIT_CONTEXT_MAX_BYTES" \
  "truncation marker should mention the env override"

echo "PASS: --diff truncates oversized sections with a clear marker"

# --- help lists the new flags ---
help_output="$(run_cli --help)"
assert_contains "$help_output" "--git-status" "--help should list --git-status"
assert_contains "$help_output" "--diff" "--help should list --diff"
assert_contains "$help_output" "102400" "--help should document the size cap"

echo "PASS: cli_git_context"

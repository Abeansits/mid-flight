log() {
  echo "[mid-flight] $*" >&2
}

error_exit() {
  local log_message="$1"
  local user_message="$2"

  log "error: $log_message"
  echo "$user_message"
  exit 1
}

init_run_workspace() {
  RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/midflight-run.XXXXXX")"
}

cleanup_run_workspace() {
  if [ -n "${RUN_DIR:-}" ] && [ -d "$RUN_DIR" ]; then
    rm -rf "$RUN_DIR"
  fi
}

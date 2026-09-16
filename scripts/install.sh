#!/usr/bin/env bash
# MidFlight CLI installer.
#
# Preferred one-liner (HTTPS only; curl -f fails on HTTP errors):
#   curl -fsSL https://raw.githubusercontent.com/Abeansits/mid-flight/main/scripts/install.sh | bash
#
# Pin a release tag (uses that tag's install.sh + matching source tarball):
#   curl -fsSL https://raw.githubusercontent.com/Abeansits/mid-flight/v1.14.0/scripts/install.sh | bash -s -- --ref v1.14.0
#
# From a local checkout (no network):
#   ./scripts/install.sh --from-dir . --prefix ~/.local
#
# Environment (also accepted as flags where noted):
#   PREFIX     install prefix (default: /usr/local if writable, else ~/.local)
#   DESTDIR    staging root for packaging (prepended to PREFIX)
#   REF        git ref: main, vX.Y.Z, or X.Y.Z (default: latest GitHub release tag, else main)
#   DRY_RUN=1  print actions only

set -euo pipefail

REPO_SLUG="Abeansits/mid-flight"
REPO_HTTPS="https://github.com/${REPO_SLUG}"
ARCHIVE_BASE="${REPO_HTTPS}/archive"

PREFIX="${PREFIX:-}"
DESTDIR="${DESTDIR:-}"
REF="${REF:-${MIDFLIGHT_REF:-}}"
FROM_DIR=""
DRY_RUN="${DRY_RUN:-0}"
PRINT_HELP=0

die() {
  printf 'midflight-install: %s\n' "$1" >&2
  exit "${2:-1}"
}

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Install the MidFlight CLI (`midflight`) onto PATH without a manual symlink
from a git clone.

Options:
  --prefix DIR       Install prefix (bin/ + lib/mid-flight/). Default: writable
                     /usr/local, else ~/.local. Env: PREFIX.
  --destdir DIR      Packaging staging root (prepended to prefix). Env: DESTDIR.
  --ref REF          Source ref: main | vX.Y.Z | X.Y.Z. Env: REF / MIDFLIGHT_REF.
                     Default: latest GitHub release tag, else main.
  --from-dir DIR     Copy from a local checkout (skips network download).
  --dry-run          Print planned actions; do not write files. Env: DRY_RUN=1.
  -h, --help         Show this help.

Layout:
  $DESTDIR$PREFIX/lib/mid-flight/   engine tree (bin/, scripts/, .claude-plugin/, …)
  $DESTDIR$PREFIX/bin/midflight     symlink → ../lib/mid-flight/bin/midflight

Examples:
  curl -fsSL https://raw.githubusercontent.com/Abeansits/mid-flight/main/scripts/install.sh | bash
  PREFIX=$HOME/.local ./scripts/install.sh --from-dir .
  ./scripts/install.sh --ref v1.14.0 --prefix /usr/local
EOF
}

log() {
  printf 'midflight-install: %s\n' "$*"
}

run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf 'midflight-install: dry-run:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "missing required command: $c"
  done
}

# Reject anything that is not an https://github.com/Abeansits/mid-flight URL.
assert_https_repo_url() {
  local url="$1"
  case "$url" in
    https://github.com/Abeansits/mid-flight/*) ;;
    https://api.github.com/repos/Abeansits/mid-flight/*) ;;
    https://codeload.github.com/Abeansits/mid-flight/*) ;;
    *) die "refusing non-HTTPS or non-repo URL: $url" ;;
  esac
}

normalize_ref() {
  local r="$1"
  if [[ "$r" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'v%s\n' "$r"
    return
  fi
  printf '%s\n' "$r"
}

default_prefix() {
  if [ -n "${PREFIX}" ]; then
    printf '%s\n' "$PREFIX"
    return
  fi
  if [ -w /usr/local/bin ] 2>/dev/null || [ -w /usr/local ] 2>/dev/null; then
    printf '/usr/local\n'
  elif mkdir -p "${HOME}/.local/bin" 2>/dev/null; then
    printf '%s/.local\n' "$HOME"
  else
    die "cannot determine PREFIX; pass --prefix DIR"
  fi
}

read_version_from_plugin() {
  local plugin_json="$1"
  [ -f "$plugin_json" ] || return 1
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$plugin_json" | head -1
}

latest_release_tag() {
  # Prefer gh when available (authenticated or not); else HTTPS API via curl.
  local tag=""
  if command -v gh >/dev/null 2>&1; then
    tag="$(gh api "repos/${REPO_SLUG}/releases/latest" --jq '.tag_name' 2>/dev/null || true)"
  fi
  if [ -z "$tag" ] || [ "$tag" = "null" ]; then
    require_cmd curl
    local api_url="https://api.github.com/repos/${REPO_SLUG}/releases/latest"
    assert_https_repo_url "$api_url"
    tag="$(curl -fsSL "$api_url" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  fi
  if [ -n "$tag" ] && [ "$tag" != "null" ]; then
    printf '%s\n' "$tag"
  else
    printf 'main\n'
  fi
}

download_tarball() {
  local ref="$1" dest_tar="$2"
  local url
  # Tags look like v1.2.3 (normalize_ref adds the v). Everything else is a branch.
  if [[ "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-].*)?$ ]]; then
    url="${ARCHIVE_BASE}/refs/tags/${ref}.tar.gz"
  else
    url="${ARCHIVE_BASE}/refs/heads/${ref}.tar.gz"
  fi
  assert_https_repo_url "$url"
  log "downloading ${url}"
  if [ "$DRY_RUN" = "1" ]; then
    log "dry-run: skip download"
    return 0
  fi
  # --proto '=https' refuses non-HTTPS redirects; -f fails on HTTP error statuses.
  curl -fsSL --proto '=https' --tlsv1.2 -o "$dest_tar" "$url" \
    || die "download failed (check REF=${ref} exists): ${url}"
}

extract_tarball() {
  local tar_path="$1" dest_dir="$2"
  require_cmd tar
  mkdir -p "$dest_dir"
  # GitHub archives nest a single top-level directory.
  tar -xzf "$tar_path" -C "$dest_dir"
  # Resolve extracted root (first directory entry).
  local extracted
  extracted="$(find "$dest_dir" -mindepth 1 -maxdepth 1 -type d | head -1)"
  [ -n "$extracted" ] || die "tarball extraction produced no directory"
  printf '%s\n' "$extracted"
}

is_engine_root() {
  local root="$1"
  [ -f "$root/bin/midflight" ] && [ -f "$root/scripts/query.sh" ] && [ -f "$root/.claude-plugin/plugin.json" ]
}

install_tree() {
  local src_root="$1"
  local prefix dest_root bindir libdir link_target

  prefix="$(default_prefix)"
  dest_root="${DESTDIR}${prefix}"
  bindir="${dest_root}/bin"
  libdir="${dest_root}/lib/mid-flight"

  is_engine_root "$src_root" || die "source tree is missing bin/midflight, scripts/query.sh, or .claude-plugin/plugin.json: $src_root"

  log "install prefix: ${DESTDIR:+DESTDIR=$DESTDIR }PREFIX=$prefix"
  log "libdir: $libdir"
  log "bindir: $bindir"

  if [ "$DRY_RUN" = "1" ]; then
    log "dry-run: would sync engine → $libdir"
    log "dry-run: would link $bindir/midflight → ../lib/mid-flight/bin/midflight"
    local ver
    ver="$(read_version_from_plugin "$src_root/.claude-plugin/plugin.json" || true)"
    log "dry-run: source version ${ver:-unknown}"
    return 0
  fi

  mkdir -p "$bindir" "$libdir"

  # Fresh install: replace libdir contents but keep other PREFIX files.
  # Use a staging dir then rename for atomic-ish replace.
  local stage
  stage="$(mktemp -d "${TMPDIR:-/tmp}/midflight-install.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$stage'" RETURN

  mkdir -p "$stage/tree"
  # Copy required paths (include dotdirs explicitly).
  local path
  for path in bin scripts commands prompts hosts docs LICENSE README.md ROADMAP.md; do
    if [ -e "$src_root/$path" ]; then
      cp -R "$src_root/$path" "$stage/tree/"
    fi
  done
  mkdir -p "$stage/tree/.claude-plugin"
  cp -R "$src_root/.claude-plugin/." "$stage/tree/.claude-plugin/"

  is_engine_root "$stage/tree" || die "staged tree incomplete"

  rm -rf "$libdir"
  mkdir -p "$(dirname "$libdir")"
  mv "$stage/tree" "$libdir"
  chmod +x "$libdir/bin/midflight"

  link_target="../lib/mid-flight/bin/midflight"
  rm -f "$bindir/midflight"
  ln -s "$link_target" "$bindir/midflight"

  local ver
  ver="$(read_version_from_plugin "$libdir/.claude-plugin/plugin.json" || true)"
  log "installed midflight ${ver:-unknown}"
  log "binary: $bindir/midflight"

  case ":$PATH:" in
    *":${dest_root}/bin:"*|*":${prefix}/bin:"*) ;;
    *)
      log "note: ensure ${prefix}/bin is on your PATH"
      ;;
  esac
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --prefix)
        [ $# -ge 2 ] || die "--prefix requires a directory"
        PREFIX="$2"
        shift 2
        ;;
      --destdir)
        [ $# -ge 2 ] || die "--destdir requires a directory"
        DESTDIR="$2"
        shift 2
        ;;
      --ref)
        [ $# -ge 2 ] || die "--ref requires a value"
        REF="$2"
        shift 2
        ;;
      --from-dir)
        [ $# -ge 2 ] || die "--from-dir requires a directory"
        FROM_DIR="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        PRINT_HELP=1
        shift
        ;;
      *)
        die "unknown option: $1 (try --help)"
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  if [ "$PRINT_HELP" = "1" ]; then
    usage
    exit 0
  fi

  require_cmd bash mkdir ln chmod mktemp cp rm mv find tar

  local src_root="" tmp=""

  if [ -n "$FROM_DIR" ]; then
    src_root="$(cd "$FROM_DIR" && pwd)" || die "cannot cd to --from-dir: $FROM_DIR"
    install_tree "$src_root"
    return 0
  fi

  require_cmd curl
  # Prefer modern curl TLS flags when supported; still require HTTPS URLs.
  if [ -z "$REF" ]; then
    REF="$(latest_release_tag)"
    log "selected ref: $REF"
  fi
  REF="$(normalize_ref "$REF")"

  if [ "$DRY_RUN" = "1" ]; then
    log "dry-run: would download ref $REF and install to PREFIX=$(default_prefix)"
    return 0
  fi

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/midflight-fetch.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  download_tarball "$REF" "$tmp/src.tar.gz"
  src_root="$(extract_tarball "$tmp/src.tar.gz" "$tmp/extract")"
  install_tree "$src_root"
}

main "$@"

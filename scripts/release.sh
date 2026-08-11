#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_JSON="$ROOT_DIR/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$ROOT_DIR/.claude-plugin/marketplace.json"

usage() {
  cat <<'EOF'
Usage:
  scripts/release.sh prepare <version>
  scripts/release.sh publish [<version>]

Commands:
  prepare <version>  Bump plugin metadata to <version> and commit it on the
                     current branch so it can go through a normal PR.
  publish [version]  Tag and publish a GitHub release from clean, up-to-date
                     main. If version is omitted, reads it from plugin.json.

Notes:
  - Run prepare on a branch, open/merge the PR, then switch to main.
  - Only run publish from a clean, up-to-date local main. Tagging from any
    other branch or a dirty main is intentionally blocked.
EOF
}

die() {
  printf 'release: %s\n' "$1" >&2
  exit 1
}

require_clean_tree() {
  if [ -n "$(git status --porcelain)" ]; then
    die "working tree is not clean"
  fi
}

require_main_branch() {
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"
  [ "$branch" = "main" ] || die "publish must run from local main (current: $branch)"
}

require_up_to_date_main() {
  local local_head remote_head
  local_head="$(git rev-parse HEAD)"
  remote_head="$(git rev-parse origin/main)"
  [ "$local_head" = "$remote_head" ] || die "local main is not up to date with origin/main"
}

require_gh() {
  # Must hold before the tag is pushed: `gh release view` failing for a missing
  # gh is indistinguishable from "no such release", and a later `gh release
  # create` failure would leave an orphaned tag on the remote.
  command -v gh >/dev/null 2>&1 || die "gh CLI is required to publish (https://cli.github.com)"
}

validate_version() {
  local version="$1"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like X.Y.Z"
}

read_version() {
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN_JSON" | head -1
}

write_versions() {
  local version="$1"

  [ -f "$PLUGIN_JSON" ] || die "missing $PLUGIN_JSON"
  [ -f "$MARKETPLACE_JSON" ] || die "missing $MARKETPLACE_JSON"

  sed -i.bak -E 's/"version"[[:space:]]*:[[:space:]]*"[^"]*"/"version": "'"$version"'"/' "$PLUGIN_JSON"
  sed -i.bak -E 's/"version"[[:space:]]*:[[:space:]]*"[^"]*"/"version": "'"$version"'"/' "$MARKETPLACE_JSON"
  rm -f "$PLUGIN_JSON.bak" "$MARKETPLACE_JSON.bak"
}

prepare_release() {
  local version="$1"
  local current_version

  validate_version "$version"
  require_clean_tree
  current_version="$(read_version)"
  [ -n "$current_version" ] || die "could not read current version from plugin.json"
  [ "$current_version" != "$version" ] || die "version is already $version"

  write_versions "$version"
  git add "$PLUGIN_JSON" "$MARKETPLACE_JSON"
  git commit -m "chore: bump version to $version"

  printf 'Prepared release commit for %s.\n' "$version"
  printf 'Next: push your branch, open/merge the PR, then run:\n'
  printf '  scripts/release.sh publish %s\n' "$version"
}

publish_release() {
  local version="${1:-}"
  local tag

  require_gh
  require_clean_tree
  require_main_branch
  git fetch origin
  require_up_to_date_main

  if [ -z "$version" ]; then
    version="$(read_version)"
  fi

  [ -n "$version" ] || die "could not determine release version"
  validate_version "$version"
  tag="v$version"

  [ "$(read_version)" = "$version" ] || die "plugin.json version does not match requested release version"
  if git rev-parse "$tag" >/dev/null 2>&1; then
    die "tag $tag already exists locally"
  fi
  if gh release view "$tag" >/dev/null 2>&1; then
    die "GitHub release $tag already exists"
  fi

  git tag "$tag"
  git push origin "$tag"
  gh release create "$tag" --generate-notes --latest

  printf 'Published %s from clean main.\n' "$tag"
}

main() {
  local cmd="${1:-}"

  case "$cmd" in
    prepare)
      [ $# -eq 2 ] || die "prepare requires a version"
      prepare_release "$2"
      ;;
    publish)
      if [ $# -gt 2 ]; then
        die "publish accepts at most one optional version"
      fi
      publish_release "${2:-}"
      ;;
    -h|--help|"")
      usage
      ;;
    *)
      die "unknown command: $cmd"
      ;;
  esac
}

main "$@"

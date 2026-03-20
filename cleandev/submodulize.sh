#!/usr/bin/env bash
# Convert vendored plugin directories (plain files in the Moodle repo, e.g. lsuce-moodle develop)
# into git submodules. Run from anywhere inside the Moodle clone; uses repo root.
#
# Requires: git, a clean enough working tree (commit or stash first if paths are dirty).
#
# Usage:
#   ./cleandev/submodulize.sh [--dry-run] [--no-commit] [--manifest PATH] [--repo ROOT]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${SCRIPT_DIR}/plugin-submodules.manifest"
DRY_RUN=false
NO_COMMIT=false
REPO_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --no-commit) NO_COMMIT=true; shift ;;
    --manifest)
      MANIFEST="${2:?}"
      shift 2
      ;;
    --repo)
      REPO_ROOT="${2:?}"
      shift 2
      ;;
    -h|--help)
      sed -n '1,20p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "Not inside a git repository. Use --repo /path/to/moodle" >&2
    exit 1
  }
fi

cd "$REPO_ROOT"

run() {
  if $DRY_RUN; then
    printf '[dry-run] %q\n' "$@"
  else
    "$@"
  fi
}

manifest_entries=0
while IFS='|' read -r raw_path raw_url raw_branch; do
  path="${raw_path#"${raw_path%%[![:space:]]*}"}"
  path="${path%"${path##*[![:space:]]}"}"
  url="${raw_url#"${raw_url%%[![:space:]]*}"}"
  url="${url%"${url##*[![:space:]]}"}"
  branch="${raw_branch#"${raw_branch%%[![:space:]]*}"}"
  branch="${branch%"${branch##*[![:space:]]}"}"

  [[ -z "$path" || "$path" =~ ^# ]] && continue
  [[ -z "$url" ]] && { echo "Manifest: missing URL for path $path" >&2; exit 1; }
  [[ -z "$branch" ]] && branch="main"

  ((++manifest_entries)) || true

  if [[ -f .gitmodules ]] && git config -f .gitmodules --get-regexp path 2>/dev/null | awk '{print $2}' | grep -Fxq "$path"; then
    echo "Already a submodule (per .gitmodules): $path — skipping"
    continue
  fi

  if [[ -d "$path/.git" ]] || [[ -f "$path/.git" ]]; then
    echo "Path already looks like a nested git repo: $path" >&2
    echo "  Remove or convert it manually, or run unsubmodulize first." >&2
    exit 1
  fi

  if [[ -e "$path" ]] && ! $DRY_RUN; then
    if ! git diff --quiet -- "$path" 2>/dev/null || ! git diff --cached --quiet -- "$path" 2>/dev/null; then
      echo "Uncommitted changes under $path — commit or stash first." >&2
      exit 1
    fi
  fi

  echo "Submodulizing: $path ← $url (branch $branch)"

  parent="$(dirname "$path")"
  if [[ "$parent" != "." ]]; then
    run mkdir -p "$parent"
  fi

  if [[ -e "$path" ]]; then
    if git ls-files --error-unmatch "$path" &>/dev/null; then
      run git rm -rf -- "$path"
    else
      run rm -rf -- "$path"
    fi
  fi

  run git submodule add -b "$branch" -- "$url" "$path"
done < "$MANIFEST"

if [[ "$manifest_entries" -eq 0 ]]; then
  echo "No entries in manifest." >&2
  exit 1
fi

if $DRY_RUN; then
  echo "Dry run complete."
  exit 0
fi

if ! $NO_COMMIT; then
  if git diff --cached --quiet 2>/dev/null; then
    echo "Nothing staged; skipping commit."
  else
    git commit -m "chore: add plugin submodules per plugin-submodules.manifest"
  fi
fi

echo "Done. Submodule layout is ready (clean repo)."

#!/usr/bin/env bash
# Replace git submodules with plain tracked directories (vendored plugins), matching lsuce-moodle
# develop style. Clones each plugin repo at the given branch, drops nested .git, and adds files
# to the parent Moodle repository.
#
# Usage:
#   ./cleandev/unsubmodulize.sh [--dry-run] [--no-commit] [--ssh] [--manifest PATH] [--repo ROOT]
#
# Use --ssh when HTTPS clones fail for private github.com repos (same as submodulize.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${SCRIPT_DIR}/plugin-submodules.manifest"
DRY_RUN=false
NO_COMMIT=false
USE_SSH=false
REPO_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --no-commit) NO_COMMIT=true; shift ;;
    --ssh) USE_SSH=true; shift ;;
    --manifest)
      MANIFEST="${2:?}"
      shift 2
      ;;
    --repo)
      REPO_ROOT="${2:?}"
      shift 2
      ;;
    -h|--help)
      sed -n '1,22p' "$0"
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

disable_sparse_checkout_if_needed() {
  $DRY_RUN && return 0
  local active=
  [[ -f .git/info/sparse-checkout ]] && active=1
  [[ "$(git config --bool core.sparseCheckout 2>/dev/null)" == "true" ]] && active=1
  [[ "$(git config --bool index.sparse 2>/dev/null)" == "true" ]] && active=1
  if [[ -z "$active" ]] && command -v git >/dev/null; then
    local listed
    listed="$(git sparse-checkout list 2>/dev/null | head -n 1 || true)"
    [[ -n "${listed// }" ]] && active=1
  fi
  [[ -z "$active" ]] && return 0
  echo "Disabling sparse-checkout so plugin paths can be vendored." >&2
  git sparse-checkout disable 2>/dev/null || true
  git config core.sparseCheckout false 2>/dev/null || true
  git config --unset-all core.sparseCheckoutCone 2>/dev/null || true
  git config index.sparse false 2>/dev/null || true
  rm -f .git/info/sparse-checkout
}

disable_sparse_checkout_if_needed

rewrite_github_url_to_ssh() {
  local u="$1"
  if $USE_SSH && [[ "$u" == https://github.com/* ]]; then
    printf '%s\n' "git@github.com:${u#https://github.com/}"
  else
    printf '%s\n' "$u"
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
  url="$(rewrite_github_url_to_ssh "$url")"

  ((++manifest_entries)) || true

  if [[ ! -f .gitmodules ]] || ! git config -f .gitmodules --get-regexp path 2>/dev/null | awk '{print $2}' | grep -Fxq "$path"; then
    echo "Not listed as submodule in .gitmodules: $path — skipping (already vendored or unknown)"
    continue
  fi

  if ! $DRY_RUN; then
    if [[ -d "$path" ]] && (cd "$path" && git status --porcelain 2>/dev/null | grep -q .); then
      echo "Submodule $path has local changes — commit/push inside submodule or stash first." >&2
      exit 1
    fi
  fi

  echo "Unsubmodulizing: $path (from $url @ $branch)"

  if $DRY_RUN; then
    printf '[dry-run] would: clone %s @ %s → %s, deinit submodule, rm .git, git add\n' "$url" "$branch" "$path"
    continue
  fi

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/unsubmodulize.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  if [[ -n "$branch" ]] && GIT_TERMINAL_PROMPT=0 git ls-remote --heads "$url" "refs/heads/$branch" 2>/dev/null | grep -q .; then
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 -b "$branch" -- "$url" "$tmp/clone"
  else
    [[ -n "$branch" ]] && echo "Remote has no branch '$branch' for $path; cloning default branch." >&2
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 -- "$url" "$tmp/clone"
  fi
  git submodule deinit -f -- "$path"
  git rm -f --sparse -- "$path" 2>/dev/null || git rm -f -- "$path"
  mod_gitdir="$(git rev-parse --git-path "modules/$path")"
  if [[ -n "$mod_gitdir" && -e "$mod_gitdir" ]]; then
    rm -rf -- "$mod_gitdir"
  fi
  parent="$(dirname "$path")"
  [[ "$parent" != "." ]] && mkdir -p "$parent"
  rm -rf -- "$path"
  cp -a "$tmp/clone/." "$path/"
  rm -rf -- "$path/.git"
  trap - EXIT
  rm -rf "$tmp"

  git -c core.sparseCheckout=false -c index.sparse=false add -- "$path"
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
    git commit -m "chore: vendor plugin trees (remove submodules per manifest)"
  fi
fi

echo "Done. Plugin directories are plain files (dirty / upstream Moodle style)."

#!/usr/bin/env bash
# Convert vendored plugin directories (plain files in the Moodle repo, e.g. lsuce-moodle develop)
# into git submodules. Run from inside the clone, or pass the clone path as ROOT / --repo.
#
# Requires: git, a clean enough working tree (commit or stash first if paths are dirty).
#
# Usage:
#   ./cleandev/submodulize.sh [ROOT] [--dry-run] [--no-commit] [--ssh] [--manifest PATH] [--repo ROOT]
#   Bare ROOT is the same as --repo (optional; may appear before or after flags).
#
# Private GitHub repos over HTTPS need credentials. Set GITHUB_TOKEN (PAT) so HTTPS URLs are rewritten
# for ls-remote / submodule add (parent repo url.insteadOf is not always applied to submodule clone).
# Or use --ssh. In Docker with no TTY you see: "could not read Username for 'https://github.com'".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${SCRIPT_DIR}/plugin-submodules.manifest"
DRY_RUN=false
NO_COMMIT=false
USE_SSH=false
REPO_ROOT=""

usage() {
  cat <<'EOF'
Convert vendored plugin directories in the Moodle repo into git submodules.
Moodle root defaults to the current directory’s git superproject (git rev-parse --show-toplevel), unless you set it explicitly.

Usage:
  submodulize.sh [ROOT] [OPTIONS...]
  submodulize.sh [OPTIONS...] [ROOT]

  ROOT — optional path to the Moodle git checkout. Give it as a single bare argument (no leading -),
         anywhere among the flags; same meaning as --repo. Only one repo path: do not pass a second
         bare path, and do not put a bare path after --repo (that is rejected).

Examples:
  submodulize.sh ~/workspace/moodle
  submodulize.sh --dry-run ~/workspace/moodle
  submodulize.sh ~/workspace/moodle --no-commit --ssh

Options:
  --dry-run       Print actions without changing the repo
  --no-commit     Stage submodule changes but do not commit
  --ssh           Use git@github.com URLs for github.com HTTPS entries
  --manifest PATH Use a manifest file (default: cleandev/plugin-submodules.manifest next to this script)
  --repo ROOT     Moodle git root (explicit form of a bare ROOT; overrides an earlier bare ROOT; a bare path after --repo is an error)

Requires: git, and a clean enough working tree (commit or stash if plugin paths are dirty).

Private GitHub over HTTPS: set GITHUB_TOKEN (PAT) so ls-remote / submodule add can authenticate,
or use --ssh. Without credentials in non-interactive environments you may see:
  could not read Username for 'https://github.com'
EOF
}

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
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -n "$REPO_ROOT" ]]; then
        echo "Unexpected argument: $1 (repo already set via --repo or positional path)" >&2
        exit 1
      fi
      REPO_ROOT="$1"
      shift
      ;;
  esac
done

if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "Not inside a git repository. Pass the Moodle root as a bare path or use --repo /path/to/moodle" >&2
    exit 1
  }
fi

cd "$REPO_ROOT"

# Moodle dev images often use sparse-checkout (cone, index.sparse, or only .git/info/sparse-checkout).
# If any of that is active, git rm / submodule add can refuse paths "outside" the cone.
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
  echo "Disabling sparse-checkout so plugin paths can be converted to submodules." >&2
  git sparse-checkout disable 2>/dev/null || true
  git config core.sparseCheckout false 2>/dev/null || true
  git config --unset-all core.sparseCheckoutCone 2>/dev/null || true
  git config index.sparse false 2>/dev/null || true
  rm -f .git/info/sparse-checkout
}

disable_sparse_checkout_if_needed

# Extra -c flags so submodule clone honors GitHub PAT (superproject local config is skipped by some git versions).
git_github_pat_c=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  git_github_pat_c+=(-c "url.https://${GITHUB_TOKEN}@github.com/.insteadOf=https://github.com/")
fi

# github.com HTTPS → SSH (git@github.com:org/repo.git) when --ssh is set.
rewrite_github_url_to_ssh() {
  local u="$1"
  if $USE_SSH && [[ "$u" == https://github.com/* ]]; then
    printf '%s\n' "git@github.com:${u#https://github.com/}"
  else
    printf '%s\n' "$u"
  fi
}

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
  url="$(rewrite_github_url_to_ssh "$url")"

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

  # Use tracked-file listing, not --error-unmatch: for a directory, Git often has no
  # single index entry named exactly $path, only files underneath — then plain rm
  # would leave the path in the index and submodule add fails.
  if [[ -n "$(git ls-files -- "$path" 2>/dev/null)" ]]; then
    if $DRY_RUN; then
      printf '[dry-run] git rm -rf [--sparse] -- %q\n' "$path"
    else
      git rm -rf --sparse -- "$path" 2>/dev/null || git rm -rf -- "$path"
    fi
  elif [[ -e "$path" ]]; then
    run rm -rf -- "$path"
  fi

  if $DRY_RUN; then
    printf '[dry-run] git submodule add -f (-b %q if exists on remote, else default branch) -- %q %q\n' "$branch" "$url" "$path"
  else
    # -f: Moodle .gitignore often ignores plugin dirs; without it submodule add fails.
    # -c overrides: sparse-checkout can still block the add otherwise.
    # Many upstream Moodle plugins use master or MOODLE_*_STABLE, not main — omit -b to use remote HEAD.
    submod_args=(-f)
    if [[ -n "$branch" ]] && GIT_TERMINAL_PROMPT=0 git "${git_github_pat_c[@]}" ls-remote --heads "$url" "refs/heads/$branch" 2>/dev/null | grep -q .; then
      submod_args+=(-b "$branch")
    else
      [[ -n "$branch" ]] && echo "Remote has no branch '$branch' for $path; using repository default branch." >&2
    fi
    if ! GIT_TERMINAL_PROMPT=0 git "${git_github_pat_c[@]}" -c core.sparseCheckout=false -c index.sparse=false submodule add "${submod_args[@]}" -- "$url" "$path"; then
      echo "submodulize: failed to add submodule $path ← $url" >&2
      echo "  If the repo is private: configure HTTPS credentials, or re-run with --ssh (needs GitHub SSH access)." >&2
      echo "  After a failed add you may need: git submodule deinit -f -- $path 2>/dev/null; rm -rf .git/modules/$path $path" >&2
      exit 1
    fi
  fi
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

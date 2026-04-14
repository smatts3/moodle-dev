#!/usr/bin/env bash
# Convert vendored plugin directories (plain files in the Moodle superproject) into git submodules.
# Intended for the submodule-layout Moodle checkout: keep plugin-submodules.manifest at the superproject
# root (same repo as .gitmodules will live in). Run from inside that clone, or pass ROOT / --repo.
# Default mode is replay: builds branch submodulized with one superproject commit per plugin-repo commit.
# Use --no-replay for one-shot conversion (manifest loop only).
#
# Requires: git, a clean enough working tree (commit or stash first if paths are dirty).
#
# Usage:
#   ./cleandev/submodulize.sh [ROOT] [--dry-run] [--no-commit] [--ssh] [--manifest PATH] [--repo ROOT]
#   ./cleandev/submodulize.sh --fork-point BASE ...   # replay (default)
#   ./cleandev/submodulize.sh --no-replay ...         # one-shot
#   Bare ROOT is the same as --repo (optional; may appear before or after flags).
#
# Private GitHub repos over HTTPS need credentials. Set GITHUB_TOKEN (PAT) so HTTPS URLs are rewritten
# for ls-remote / submodule add (parent repo url.insteadOf is not always applied to submodule clone).
# Or use --ssh. In Docker with no TTY you see: "could not read Username for 'https://github.com'".
#
# Requires bash (arrays, pipefail). Do not run as `sh this-script.sh`; use `bash` or execute directly.

if [ -z "${BASH_VERSION:-}" ]; then
  printf '%s: requires bash, not sh. Example: bash "%s" ./ ...your args...\n' "${0##*/}" "$0" >&2
  exit 1
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MANIFEST=""
MANIFEST_EXPLICIT=false
DRY_RUN=false
NO_COMMIT=false
USE_SSH=false
REPO_ROOT=""
REPLAY=true
FORK_POINT=""
SOURCE_BRANCH=""
TARGET_BRANCH="submodulized"
REPLAY_ORDER="chronological"
FORCE_REPLAY=false
REPLAY_SOURCE_EXPLICIT=false
REPLAY_TARGET_EXPLICIT=false
REPLAY_ORDER_EXPLICIT=false
FORK_POINT_EXPLICIT=false
BOOTSTRAP=false
BOOTSTRAP_EXPLICIT=false
declare -a PLUGIN_BASE_OVERRIDES=()

usage() {
  cat <<'EOF'
Convert vendored plugin directories in the Moodle superproject into git submodules (cleandev-style).
The manifest lists paths and clone URLs; it normally lives in the superproject root as
plugin-submodules.manifest (not under cleandev/). Moodle root defaults to the current directory’s
git superproject (git rev-parse --show-toplevel), unless you set it explicitly.

Usage:
  submodulize.sh [ROOT] [OPTIONS...]
  submodulize.sh [OPTIONS...] [ROOT]

  ROOT — optional path to the Moodle git checkout. Give it as a single bare argument (no leading -),
         anywhere among the flags; same meaning as --repo. Only one repo path: do not pass a second
         bare path, and do not put a bare path after --repo (that is rejected).

Examples:
  submodulize.sh --no-replay ~/workspace/moodle
  submodulize.sh ./ --bootstrap
  submodulize.sh ./   # same as --bootstrap when submodulized branch does not exist yet
  submodulize.sh --dry-run --no-replay ~/workspace/moodle
  submodulize.sh --fork-point abc123 --source submodulized

Options:
  --dry-run       Print actions without changing the repo
  --no-commit     Stage submodule changes but do not commit
  --ssh           Use git@github.com URLs for github.com HTTPS entries
  --manifest PATH Plugin manifest (default: ROOT/plugin-submodules.manifest)
  --repo ROOT     Moodle git root (explicit form of a bare ROOT; overrides an earlier bare ROOT; a bare path after --repo is an error)

Bootstrap (from vendored tree + manifest → submodulized + unsubmodulized):
  --bootstrap           Add submodules on branch submodulized, then run unsubmodulize replay to create unsubmodulized.
                        If local branch submodulized is missing, this runs automatically (same as passing --bootstrap).

Replay (default — one superproject commit per plugin-repo commit on --target):
  --no-replay           One-shot mode: add submodules per manifest (no branch replay)
  --replay              Replay mode (default; explicit if you toggled --no-replay earlier on the command line)
  --fork-point BASE     Start of replay (default: local master, else main, when omitted — see docs)
  --source BR           End state per path (gitlinks and/or vendored trees; default: submodulized, else master, else main)
  --target BR           Branch to create/update (default: submodulized)
  --order NAME          Only chronological
  --force               Overwrite --target branch if it exists (replay only)
  --plugin-base P=S     Optional start SHA for manifest path P

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
    --no-replay) REPLAY=false; shift ;;
    --replay) REPLAY=true; shift ;;
    --bootstrap)
      BOOTSTRAP=true
      BOOTSTRAP_EXPLICIT=true
      REPLAY=false
      shift
      ;;
    --fork-point)
      FORK_POINT="${2:?}"
      FORK_POINT_EXPLICIT=true
      shift 2
      ;;
    --source)
      SOURCE_BRANCH="${2:?}"
      REPLAY_SOURCE_EXPLICIT=true
      shift 2
      ;;
    --target)
      TARGET_BRANCH="${2:?}"
      REPLAY_TARGET_EXPLICIT=true
      shift 2
      ;;
    --order)
      REPLAY_ORDER="${2:?}"
      REPLAY_ORDER_EXPLICIT=true
      shift 2
      ;;
    --force)
      FORCE_REPLAY=true
      shift
      ;;
    --plugin-base)
      PLUGIN_BASE_OVERRIDES+=("${2:?}")
      shift 2
      ;;
    --manifest)
      MANIFEST="${2:?}"
      MANIFEST_EXPLICIT=true
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

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "Not inside a git repository. Pass the Moodle root as a bare path or use --repo /path/to/moodle" >&2
    exit 1
  }
fi

if ! $MANIFEST_EXPLICIT; then
  MANIFEST="${REPO_ROOT%/}/plugin-submodules.manifest"
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

if $BOOTSTRAP_EXPLICIT; then
  $FORK_POINT_EXPLICIT && {
    echo "Do not combine --bootstrap with --fork-point (bootstrap records the current commit as the fork)." >&2
    exit 1
  }
  $REPLAY_SOURCE_EXPLICIT && {
    echo "Do not combine --bootstrap with --source (bootstrap uses submodulized → unsubmodulized)." >&2
    exit 1
  }
  $REPLAY_TARGET_EXPLICIT && {
    echo "Do not combine --bootstrap with --target." >&2
    exit 1
  }
  $REPLAY_ORDER_EXPLICIT && {
    echo "Do not combine --bootstrap with --order." >&2
    exit 1
  }
  ((${#PLUGIN_BASE_OVERRIDES[@]} == 0)) || {
    echo "--plugin-base is not used with --bootstrap." >&2
    exit 1
  }
fi

cd "$REPO_ROOT"

# Greenfield: no submodulized branch yet — run bootstrap (one-shot + unsub replay) instead of sub replay.
if $REPLAY && ! $FORK_POINT_EXPLICIT && ! $BOOTSTRAP_EXPLICIT && ! git show-ref --verify --quiet refs/heads/submodulized; then
  BOOTSTRAP=true
  REPLAY=false
  echo "submodulize: no local branch submodulized — bootstrap (add submodules, then build unsubmodulized)." >&2
fi

if $REPLAY; then
  [[ "$REPLAY_ORDER" == "chronological" ]] || {
    echo "Only --order chronological is supported: $REPLAY_ORDER" >&2
    exit 1
  }
elif $BOOTSTRAP; then
  :
else
  [[ -z "$FORK_POINT" ]] || {
    echo "--fork-point is only used in replay mode (omit --no-replay)" >&2
    exit 1
  }
  ((${#PLUGIN_BASE_OVERRIDES[@]} == 0)) || {
    echo "--plugin-base is only valid in replay mode (omit --no-replay)" >&2
    exit 1
  }
  $FORCE_REPLAY && {
    echo "--force is only valid in replay mode or bootstrap (omit --no-replay)" >&2
    exit 1
  }
  $REPLAY_SOURCE_EXPLICIT && {
    echo "--source is only valid in replay mode (omit --no-replay)" >&2
    exit 1
  }
  $REPLAY_TARGET_EXPLICIT && {
    echo "--target is only valid in replay mode (omit --no-replay)" >&2
    exit 1
  }
  $REPLAY_ORDER_EXPLICIT && {
    echo "--order is only valid in replay mode (omit --no-replay)" >&2
    exit 1
  }
fi

# When --fork-point is omitted in replay mode, default to local master (else main) if safe.
if $REPLAY && [[ -z "$FORK_POINT" ]]; then
  base_ref=""
  if git show-ref --verify --quiet refs/heads/master; then
    base_ref=master
  elif git show-ref --verify --quiet refs/heads/main; then
    base_ref=main
  else
    echo "Replay needs --fork-point (no local master or main branch to use as default)." >&2
    exit 1
  fi
  head_sha="$(git rev-parse HEAD)"
  master_sha="$(git rev-parse "${base_ref}^{commit}")"
  target_exists=false
  git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH" && target_exists=true
  if ! $target_exists; then
    FORK_POINT="$base_ref"
    echo "Default --fork-point $FORK_POINT ($TARGET_BRANCH does not exist yet)." >&2
  else
    target_sha="$(git rev-parse "$TARGET_BRANCH^{commit}")"
    if [[ "$head_sha" == "$master_sha" ]] || [[ "$head_sha" == "$target_sha" ]]; then
      FORK_POINT="$base_ref"
      echo "Default --fork-point $FORK_POINT (HEAD is ${base_ref} or $TARGET_BRANCH)." >&2
    else
      FORK_POINT="$base_ref"
      echo "Default --fork-point $FORK_POINT (recreating $TARGET_BRANCH from ${base_ref}; use --force if the branch already exists)." >&2
    fi
  fi
fi

# When --source is omitted in replay mode: prefer submodulized, else master, else main.
if $REPLAY && ! $REPLAY_SOURCE_EXPLICIT; then
  if git show-ref --verify --quiet refs/heads/submodulized; then
    SOURCE_BRANCH=submodulized
  elif git show-ref --verify --quiet refs/heads/master; then
    SOURCE_BRANCH=master
  elif git show-ref --verify --quiet refs/heads/main; then
    SOURCE_BRANCH=main
  else
    echo "Replay: pass --source BR (no local submodulized, master, or main branch found)." >&2
    exit 1
  fi
  echo "Default --source $SOURCE_BRANCH" >&2
fi

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

submodulize_one_shot_apply_manifest() {
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
    $BOOTSTRAP && echo "Bootstrap: would commit on submodulized, then run unsubmodulize replay (omit --dry-run)." >&2
    exit 0
  fi

  if ! $NO_COMMIT; then
    if git diff --cached --quiet 2>/dev/null; then
      echo "Nothing staged; skipping commit."
    else
      git commit -m "chore: add plugin submodules per plugin-submodules.manifest"
    fi
  fi

  $BOOTSTRAP || echo "Done. Submodule layout is ready (clean repo)."
}

submodulize_bootstrap_pipeline() {
  local vend_tip unsub_args
  vend_tip="$(git rev-parse HEAD)"
  echo "Bootstrap: vendored fork-point for unsub replay: $vend_tip" >&2

  if git show-ref --verify --quiet refs/heads/submodulized && ! $FORCE_REPLAY; then
    echo "Branch submodulized already exists. Use --force to replace it, delete the branch, or run without bootstrap." >&2
    exit 1
  fi
  $FORCE_REPLAY && git branch -D submodulized 2>/dev/null || true

  git checkout -B submodulized

  submodulize_one_shot_apply_manifest

  if $DRY_RUN; then
    exit 0
  fi

  unsub_args=(--repo "$REPO_ROOT" --fork-point "$vend_tip" --source submodulized --target unsubmodulized)
  $FORCE_REPLAY && unsub_args+=(--force)

  bash "$SCRIPT_DIR/unsubmodulize.sh" "${unsub_args[@]}"
  echo "Bootstrap complete: submodulized (submodules) and unsubmodulized (vendored replay) are ready." >&2
}

submodulize_replay_mode() {
  git rev-parse --verify "$FORK_POINT^{commit}" >/dev/null
  git rev-parse --verify "$SOURCE_BRANCH^{commit}" >/dev/null

  if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH" && ! $FORCE_REPLAY; then
    echo "Branch $TARGET_BRANCH exists; pass --force" >&2
    exit 1
  fi

  ls_path_mode_sha() {
    git ls-tree "$1" -- "$2" 2>/dev/null | awk '{print $1 "\t" $3}' | head -n1
  }

  plugin_base_override_for() {
    local want="$1" entry
    for entry in "${PLUGIN_BASE_OVERRIDES[@]:-}"; do
      [[ "${entry%%=*}" == "$want" ]] && { echo "${entry#*=}"; return 0; }
    done
    return 1
  }

  find_plugin_commit_for_tree() {
    local pdir="$1" want_tree="$2" c t
    while IFS= read -r c; do
      t="$(git -C "$pdir" rev-parse "$c^{tree}" 2>/dev/null || true)"
      [[ "$t" == "$want_tree" ]] && { echo "$c"; return 0; }
    done < <(git -C "$pdir" rev-list --first-parent --reverse --all)
    return 1
  }

  declare -a M_PATHS=() M_URLS=() M_BRANCHES=()

  while IFS='|' read -r raw_path raw_url raw_branch; do
    path="${raw_path#"${raw_path%%[![:space:]]*}"}"
    path="${path%"${path##*[![:space:]]}"}"
    url="${raw_url#"${raw_url%%[![:space:]]*}"}"
    url="${url%"${url##*[![:space:]]}"}"
    branch="${raw_branch#"${raw_branch%%[![:space:]]*}"}"
    branch="${branch%"${branch##*[![:space:]]}"}"
    [[ -z "$path" || "$path" =~ ^# ]] && continue
    [[ -z "$url" ]] && { echo "Manifest: missing URL for $path" >&2; exit 1; }
    [[ -z "$branch" ]] && branch="main"
    M_PATHS+=("$path")
    M_URLS+=("$url")
    M_BRANCHES+=("$branch")
  done < "$MANIFEST"

  [[ ${#M_PATHS[@]} -gt 0 ]] || { echo "No manifest entries." >&2; exit 1; }

  SOURCE_TIP="$(git rev-parse "$SOURCE_BRANCH^{commit}")"
  TMPD="$(mktemp -d "${TMPDIR:-/tmp}/sub-replay.XXXXXX")"
  trap 'rm -rf "$TMPD"' EXIT

  declare -a EVENT_LINES=()

  for i in "${!M_PATHS[@]}"; do
    P="${M_PATHS[$i]}"
    URL="$(rewrite_github_url_to_ssh "${M_URLS[$i]}")"
    PDIR="$TMPD/plugin_${i}_$(echo "$P" | tr '/' '_')"

    ms="$(ls_path_mode_sha "$FORK_POINT" "$P")"
    mode="${ms%%$'\t'*}"
    from_sha="${ms#*$'\t'}"

    ms2="$(ls_path_mode_sha "$SOURCE_TIP" "$P")"
    to_sha="${ms2#*$'\t'}"
    mode2="${ms2%%$'\t'*}"

    if [[ ! -d "$PDIR/.git" ]]; then
      GIT_TERMINAL_PROMPT=0 git "${git_github_pat_c[@]}" clone --bare "$URL" "$PDIR"
    fi
    GIT_TERMINAL_PROMPT=0 git -C "$PDIR" fetch -q origin 2>/dev/null || true
    GIT_TERMINAL_PROMPT=0 git -C "$PDIR" fetch -q "$URL" "+refs/*:refs/remotes/import/*" 2>/dev/null || true

    if [[ "$mode2" == "160000" && -n "$to_sha" ]]; then
      :
    elif [[ "$mode2" == "040000" ]]; then
      tr_end="$(git rev-parse "$SOURCE_TIP:$P^{tree}" 2>/dev/null || true)"
      if [[ -z "$tr_end" ]]; then
        echo "No tree at $SOURCE_BRANCH:$P (source tip)" >&2
        exit 1
      fi
      to_sha="$(find_plugin_commit_for_tree "$PDIR" "$tr_end")" || {
        echo "Could not match plugin commit to vendored tree at $SOURCE_BRANCH:$P" >&2
        exit 1
      }
    else
      echo "Path $P: source tip must be gitlink or vendored directory for end SHA" >&2
      exit 1
    fi

    if ! plugin_base_override_for "$P" >/dev/null; then
      if [[ "$mode" == "160000" && -n "$from_sha" ]]; then
        :
      elif [[ "$mode" == "040000" ]]; then
        tr_sha="$(git rev-parse "$FORK_POINT:$P^{tree}" 2>/dev/null || true)"
        if [[ -z "$tr_sha" ]]; then
          echo "No tree at $FORK_POINT:$P" >&2
          exit 1
        fi
        from_sha="$(find_plugin_commit_for_tree "$PDIR" "$tr_sha")" || {
          echo "Could not find plugin commit matching tree at $FORK_POINT:$P" >&2
          exit 1
        }
      else
        echo "Path $P at fork-point must be gitlink or directory; use --plugin-base ${P}=SHA" >&2
        exit 1
      fi
    else
      from_sha="$(plugin_base_override_for "$P")"
    fi

    GIT_TERMINAL_PROMPT=0 git -C "$PDIR" cat-file -e "${from_sha}^{commit}" 2>/dev/null || {
      echo "Missing plugin object $from_sha for $P" >&2
      exit 1
    }
    GIT_TERMINAL_PROMPT=0 git -C "$PDIR" cat-file -e "${to_sha}^{commit}" 2>/dev/null || {
      echo "Missing plugin object $to_sha for $P" >&2
      exit 1
    }

    mapfile -t PCOMMITS < <(GIT_TERMINAL_PROMPT=0 git -C "$PDIR" rev-list --first-parent --reverse "${from_sha}..${to_sha}")
    [[ ${#PCOMMITS[@]} -eq 0 ]] && continue

    for c in "${PCOMMITS[@]}"; do
      ct="$(git -C "$PDIR" show -s --format=%ct "$c")"
      EVENT_LINES+=("${ct}"$'\t'"${P}"$'\t'"${c}"$'\t'"${PDIR}"$'\t'"${M_URLS[$i]}")
    done
  done

  [[ ${#EVENT_LINES[@]} -gt 0 ]] || { echo "No plugin commits to replay." >&2; exit 0; }

  IFS=$'\n'
  sorted="$(printf '%s\n' "${EVENT_LINES[@]}" | LC_ALL=C sort -t $'\t' -k1,1n -k2,2 -k3,3)"
  unset IFS

  if $DRY_RUN; then
    echo "Planned ${#EVENT_LINES[@]} commits on $TARGET_BRANCH (from $FORK_POINT)"
    while IFS=$'\t' read -r ct p sha pdir url; do
      [[ -z "${ct:-}" ]] && continue
      echo "  $ct  $p  $sha  ($(git -C "$pdir" show -s --format=%s "$sha"))"
    done <<< "$sorted"
    exit 0
  fi

  $FORCE_REPLAY && git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH" && git branch -D "$TARGET_BRANCH" 2>/dev/null || true
  git worktree prune 2>/dev/null || true

  WT="$TMPD/wt"
  rm -rf "$WT"

  manifest_url_for_path() {
    local want="$1" _i
    for _i in "${!M_PATHS[@]}"; do
      if [[ "${M_PATHS[$_i]}" == "$want" ]]; then
        echo "${M_URLS[$_i]}"
        return 0
      fi
    done
    return 1
  }

  rebuild_gitmodules() {
    rm -f "$WT/.gitmodules"
    git -C "$WT" ls-files -s | while read -r mode sha _st path; do
      [[ "$mode" == "160000" ]] || continue
      u="$(manifest_url_for_path "$path")" || continue
      printf '[submodule "%s"]\n\tpath = %s\n\turl = %s\n' "$path" "$path" "$u" >>"$WT/.gitmodules"
    done
  }

  GIT_TERMINAL_PROMPT=0 git "${git_github_pat_c[@]}" worktree add -B "$TARGET_BRANCH" "$WT" "$FORK_POINT" --force

  while IFS=$'\t' read -r ct P csha pdir url; do
    [[ -z "${ct:-}" ]] && continue
    git -C "$WT" reset --hard -q HEAD
    git -C "$WT" rm -rf --cached --ignore-unmatch "$P" 2>/dev/null || true
    rm -rf "${WT:?}/${P}"
    git -C "$WT" update-index --add --cacheinfo "160000,$csha,$P"
    rebuild_gitmodules
    git -C "$WT" add -f .gitmodules 2>/dev/null || true

    an="$(git -C "$pdir" show -s --format=%an "$csha")"
    ae="$(git -C "$pdir" show -s --format=%ae "$csha")"
    adate="$(git -C "$pdir" show -s --format=%ai "$csha")"
    body="$(git -C "$pdir" show -s --format=%B "$csha")"
    {
      printf '%s\n\n' "$body"
      printf 'Replayed-from: %s\n' "$csha"
      printf 'Plugin-path: %s\n' "$P"
      printf 'gitlink: submodulize.sh (replay)\n'
    } >"$TMPD/commitmsg.txt"

    GIT_AUTHOR_NAME="$an" GIT_AUTHOR_EMAIL="$ae" GIT_AUTHOR_DATE="$adate" \
      GIT_COMMITTER_NAME="$an" GIT_COMMITTER_EMAIL="$ae" GIT_COMMITTER_DATE="$adate" \
      git -C "$WT" commit -F "$TMPD/commitmsg.txt"
  done <<< "$sorted"

  git -C "$REPO_ROOT" worktree remove -f "$WT" 2>/dev/null || true
  echo "Done. Branch $TARGET_BRANCH -> $(git rev-parse "$TARGET_BRANCH")"
}

if $BOOTSTRAP; then
  submodulize_bootstrap_pipeline
  exit 0
fi

if $REPLAY; then
  submodulize_replay_mode
  exit 0
fi

submodulize_one_shot_apply_manifest
exit 0

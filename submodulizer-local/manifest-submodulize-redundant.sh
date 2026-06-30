#!/usr/bin/env bash
# Exit 0 if running submodulize.sh would be a no-op: every active manifest plugin path is already listed
# in .gitmodules and .gitmodules is non-empty. Exit 1 otherwise (submodulize should run).
# Used by new.sh --submodulize and submodulizer/tests.
# Default manifest: ROOT/submodulizer.json (same as submodulize.sh). Requires jq.
# Active = plugins that are not disabled and have a non-empty url (no_clone/disabled entries
# cannot become submodules, matching submodulize.sh's load_manifest selection).
#
# Usage: ./submodulizer-local/manifest-submodulize-redundant.sh --repo ROOT [--manifest PATH]
set -euo pipefail

REPO_ROOT=""
MANIFEST=""
MANIFEST_EXPLICIT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_ROOT="${2:?}"
      shift 2
      ;;
    --manifest)
      MANIFEST="${2:?}"
      MANIFEST_EXPLICIT=true
      shift 2
      ;;
    -h|--help)
      sed -n '1,9p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

[[ -n "$REPO_ROOT" ]] || {
  echo "Usage: $0 --repo ROOT [--manifest PATH]" >&2
  echo "  Default manifest: ROOT/submodulizer.json" >&2
  exit 2
}

if ! $MANIFEST_EXPLICIT; then
  MANIFEST="${REPO_ROOT%/}/submodulizer.json"
fi

[[ -f "$MANIFEST" ]] || {
  echo "Manifest not found: $MANIFEST" >&2
  exit 2
}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to read submodulizer.json. Install with your package manager (e.g. 'apt install jq', 'brew install jq')." >&2
  exit 2
fi

cd "$REPO_ROOT"

declare -a active_paths=()
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  active_paths+=("$p")
done < <(jq -r '.plugins[] | select(.disabled != true) | select((.url // "") != "") | .path' "$MANIFEST" | tr -d '\r')

active=${#active_paths[@]}
if [[ "$active" -eq 0 ]]; then
  exit 1
fi

need_submod=0
for p in "${active_paths[@]}"; do
  if ! git config -f .gitmodules --get-regexp path 2>/dev/null | awk '{print $2}' | grep -Fxq "$p"; then
    need_submod=1
    break
  fi
done

if [[ "$need_submod" -eq 0 && -s .gitmodules ]]; then
  exit 0
fi
exit 1

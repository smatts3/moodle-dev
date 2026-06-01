#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# lsuonline/moodleus is a private repo; the Dockerfile clones it via a BuildKit
# secret. Resolve+export GITHUB_TOKEN, then pass --secret so docker build can
# mount it. See submodulizer-local/lib-github-token.sh for sources/prompts.
# shellcheck source=submodulizer-local/lib-github-token.sh
. "${SCRIPT_DIR}/submodulizer-local/lib-github-token.sh"
resolve_github_token || exit 1

DOCKER_BUILDKIT=1 docker build \
    --secret id=github_token,env=GITHUB_TOKEN \
    -t lsuonline/moodle-dev:latest "$@" .

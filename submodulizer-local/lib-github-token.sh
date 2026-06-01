#!/usr/bin/env bash
# lib-github-token.sh -- sourced by new.sh and build.sh.
#
# Defines resolve_github_token(): on success, GITHUB_TOKEN is set and exported,
# so docker compose / docker build can forward it to the BuildKit secret
# `github_token` consumed by Dockerfile. Returns non-zero (and prints guidance)
# when no source provides a token.
#
# Sources, in order:
#   1. GITHUB_TOKEN env var (already set)
#   2. GH_TOKEN env var
#   3. submodulizer-local/.github-token file (next to this lib)
#   4. Interactive prompt (TTY only); persists to the file above (chmod 600)
#
# SUBMODULIZE_SSH=1 is intentionally NOT honored here: the Docker build always
# clones lsuonline/moodleus over HTTPS, regardless of how the in-container
# submodulize step in new.sh chooses to authenticate later.

resolve_github_token() {
    local lib_dir token_file value
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    token_file="${lib_dir}/.github-token"

    if [ -n "${GITHUB_TOKEN:-}" ]; then
        export GITHUB_TOKEN
        return 0
    fi
    if [ -n "${GH_TOKEN:-}" ]; then
        GITHUB_TOKEN="$GH_TOKEN"
        export GITHUB_TOKEN
        return 0
    fi
    if [ -f "$token_file" ]; then
        value="$(
            grep -v '^[[:space:]]*#' "$token_file" 2>/dev/null \
                | grep -v '^[[:space:]]*$' | head -n1 | tr -d '\r' \
                | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
        )"
        if [ -n "$value" ]; then
            GITHUB_TOKEN="$value"
            export GITHUB_TOKEN
            return 0
        fi
    fi
    if [ -t 0 ] && [ -t 1 ]; then
        echo "GitHub personal access token needed: the Docker build clones private lsuonline/moodleus." >&2
        echo "Read scope on lsuonline/* repos is enough. Token will be saved to" >&2
        echo "  ${token_file} (gitignored, chmod 600)." >&2
        read -r -s -p "GitHub token: " value
        echo >&2
        if [ -n "$value" ]; then
            mkdir -p "$(dirname "$token_file")"
            ( umask 077 && printf '%s\n' "$value" >"$token_file" )
            chmod 600 "$token_file" 2>/dev/null || true
            echo "Token stored in submodulizer-local/.github-token" >&2
            GITHUB_TOKEN="$value"
            export GITHUB_TOKEN
            return 0
        fi
    fi
    echo "lib-github-token.sh: No GitHub token resolved. lsuonline/moodleus is private," >&2
    echo "  so the Docker build cannot clone it. Options:" >&2
    echo "    - export GITHUB_TOKEN (or GH_TOKEN) before re-running" >&2
    echo "    - create ${token_file}" >&2
    echo "    - run the script in a terminal to be prompted" >&2
    return 1
}

#!/usr/bin/env bash
set -euo pipefail

TRAEFIK_NETWORK="traefik"
TRAEFIK_CONTAINER="traefik"

function cursorBack() {
  echo -en "\033[$1D"
}

function spinner() {
    local LC_CTYPE=C

    local pid=$1
    # local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    # local spin='⠁⠉⠙⠹⠽⠿⠾⠶⠦⠆⠂⠀'
    local spin='⠁⠉⠙⠹⠽⠾⠷⠯⠟⠻⠽⠾⠶⠦⠆⠂⠀'
    local charwidth=3

    local i=0
    tput civis
    while kill -0 $pid 2>/dev/null; do
        local i=$(((i + $charwidth) % ${#spin}))
        printf "%s" "${spin:$i:$charwidth}"

        cursorBack 1
        sleep .016
    done
    tput cnorm
    wait $pid
    cursorBack 1
    echo " "

    return $?
}

# Git Bash / MSYS + Docker Desktop: docker cp SOURCE must be a Windows path or //drive/...;
# otherwise paths like /c/Users/... become C:\c and fail with GetFileAttributesEx.
host_path_for_docker_cp() {
    local f="$1"
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*)
            if command -v cygpath >/dev/null 2>&1; then
                cygpath -w "$f"
                return
            fi
            case "$f" in
                /[a-zA-Z]/*)
                    printf '//%s' "${f#/}"
                    return
                    ;;
            esac
            ;;
    esac
    printf '%s' "$f"
}

# Ensure the traefik network exists
ensure_traefik_network() {
    if ! docker network inspect "$TRAEFIK_NETWORK" &>/dev/null; then
        echo "Creating traefik network..."
        docker network create "$TRAEFIK_NETWORK"
    fi
}

# Ensure Traefik is running
ensure_traefik_running() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${TRAEFIK_CONTAINER}$"; then
        echo "Starting Traefik..."
        docker run -d \
            --name "$TRAEFIK_CONTAINER" \
            --restart always \
            --network "$TRAEFIK_NETWORK" \
            -p 80:80 \
            -p 8080:8080 \
            -v //var/run/docker.sock:/var/run/docker.sock:ro \
            traefik:v3.0 \
            --api.insecure=true \
            --providers.docker=true \
            --providers.docker.exposedbydefault=false \
            --providers.docker.network="$TRAEFIK_NETWORK" \
            --entrypoints.web.address=:80
        echo "Traefik started. Dashboard available at http://localhost:8080"
    fi
}

# Set a Moodle config value via CLI
# Usage: set_config [component] name value
#   - If component is empty or "-", sets a core config
resolve_submod_github_token() {
    local github_token_file="${PROJECT_ROOT}/submodulizer-local/.github-token"
    SUBMOD_GIT_TOKEN=""
    if [ "${SUBMODULIZE_SSH:-}" = "1" ]; then
        return 0
    fi
    SUBMOD_GIT_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    if [ -n "$SUBMOD_GIT_TOKEN" ]; then
        return 0
    fi
    if [ -f "$github_token_file" ]; then
        SUBMOD_GIT_TOKEN="$(
            grep -v '^[[:space:]]*#' "$github_token_file" 2>/dev/null |
                grep -v '^[[:space:]]*$' | head -n1 | tr -d '\r' |
                sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
        )"
    fi
    if [ -n "$SUBMOD_GIT_TOKEN" ]; then
        return 0
    fi
    if [ -t 0 ] && [ -t 1 ]; then
        echo "GitHub personal access token needed for private submodule repos (read access to org repos)." >&2
        echo "Saved to submodulizer-local/.github-token (gitignored). Use SUBMODULIZE_SSH=1 instead if you use SSH in the container." >&2
        read -r -s -p "GitHub token: " SUBMOD_GIT_TOKEN
        echo >&2
        if [ -n "$SUBMOD_GIT_TOKEN" ]; then
            mkdir -p "$(dirname "$github_token_file")"
            ( umask 077 && printf '%s\n' "$SUBMOD_GIT_TOKEN" >"$github_token_file" )
            chmod 600 "$github_token_file" 2>/dev/null || true
            echo "Token stored in submodulizer-local/.github-token" >&2
        fi
    fi
    if [ -n "$SUBMOD_GIT_TOKEN" ]; then
        return 0
    fi
    echo "new.sh: No GitHub token for --submodulize. Options: export GITHUB_TOKEN or GH_TOKEN, create submodulizer-local/.github-token," >&2
    echo "  run this script in a terminal (interactive prompt), or set SUBMODULIZE_SSH=1 for SSH URLs." >&2
    exit 1
}

set_config() {
    local component="$1"
    local name="$2"
    local value="$3"
    local confidential="${4:-false}"

    if [ "$confidential" = true ]; then
        echo -n "Setting confidential config: $component | $name | ***** "
    else
        echo -n "Setting config: $component | $name | $value "
    fi
    
    if [ -z "$component" ] || [ "$component" = "-" ]; then
        MSYS_NO_PATHCONV=1 docker exec -u www-data "${NAME}-moodle" php /var/www/html/admin/cli/cfg.php \
            --name="$name" \
            --set="$value" \
            & spinner $!
    else
        MSYS_NO_PATHCONV=1 docker exec -u www-data "${NAME}-moodle" php /var/www/html/admin/cli/cfg.php \
            --component="$component" \
            --name="$name" \
            --set="$value" \
            & spinner $!
    fi
}

SKIP_INSTALL=false
SUBMODULIZE=false
NAME=""
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: new.sh [OPTION]... [NAME]
    Creates a new dev environment named NAME (or random if not provided).
    Options:
        -h --help        Shows this text.
        -s --skip        Skip automatic Moodle installation.
        --submodulize    After merge, run submodulizer/submodulize.sh --no-replay for manifest plugins (submodules).
                         Safe on cleandev-style trees: paths already in .gitmodules are skipped (no bulk no-op run).
                         GitHub auth (private lsuonline/*): GITHUB_TOKEN or GH_TOKEN, file submodulizer-local/.github-token,
                         or an interactive prompt (first run) saves the token there (gitignored). Alternatively
                         SUBMODULIZE_SSH=1 with SSH usable inside the container.";
            exit;
            ;;
        -s|--skip)
            SKIP_INSTALL=true
            shift
            ;;
        --submodulize)
            SUBMODULIZE=true
            shift
            ;;
        *)
            if [ -z "$NAME" ]; then
                NAME=$1
            fi
            shift
            ;;
    esac
done

# If no name provided, use a random one
if [ -z "$NAME" ]; then
    NAME=$(dd if=/dev/urandom bs=2 count=1 2>/dev/null | od -An -t x1 | tr -d ' \n')
fi

# Populated when --submodulize runs (env, submodulizer-local/.github-token, or prompt).
SUBMOD_GIT_TOKEN=""

# Resolve a GitHub token now: the Docker build clones the private lsuonline/moodleus
# repo, so GITHUB_TOKEN must be exported before `docker compose up` so the
# `github_token` build secret declared in docker-compose.yml can pick it up.
# The same token is reused for --submodulize further down (no second prompt).
# shellcheck source=submodulizer-local/lib-github-token.sh
. "${PROJECT_ROOT}/submodulizer-local/lib-github-token.sh"
resolve_github_token || exit 1

# Ensure Traefik infrastructure is ready
ensure_traefik_network
ensure_traefik_running

BRANCH_NAME=$NAME docker compose -p "${NAME}" up -d

# Update the container with the latest code. Remove blocks/ues_people so merge does not abort (name clash
# with block_lsu_people). skip-worktree on ues_people and config.php for a clean git status after startup.
# enrol/workdaystudent and blocks/wdsprefs come from the lsuce-moodle tree (or --submodulize manifest).
if [ "$SUBMODULIZE" = true ]; then
  if [ ! -f "${PROJECT_ROOT}/submodulizer/submodulize.sh" ] || [ ! -f "${PROJECT_ROOT}/submodulizer-local/manifest-submodulize-redundant.sh" ] || [ ! -f "${PROJECT_ROOT}/submodulizer-local/plugin-submodules.manifest" ]; then
    echo "new.sh --submodulize requires submodulizer/submodulize.sh (submodule; run 'git submodule update --init --recursive'), submodulizer-local/manifest-submodulize-redundant.sh, and submodulizer-local/plugin-submodules.manifest." >&2
    exit 1
  fi
  resolve_submod_github_token
  MSYS_NO_PATHCONV=1 docker cp "$(host_path_for_docker_cp "${PROJECT_ROOT}/submodulizer/submodulize.sh")" "${NAME}-moodle:/tmp/submodulize.sh"
  MSYS_NO_PATHCONV=1 docker cp "$(host_path_for_docker_cp "${PROJECT_ROOT}/submodulizer-local/manifest-submodulize-redundant.sh")" "${NAME}-moodle:/tmp/manifest-submodulize-redundant.sh"
  MSYS_NO_PATHCONV=1 docker cp "$(host_path_for_docker_cp "${PROJECT_ROOT}/submodulizer-local/plugin-submodules.manifest")" "${NAME}-moodle:/tmp/plugin-submodules.manifest"
  # docker cp leaves root-owned files; sed -i as www-data fails with "cannot rename: Operation not permitted"
  MSYS_NO_PATHCONV=1 docker exec "${NAME}-moodle" sh -c 'sed -i '"'"'s/\r$//'"'"' /tmp/submodulize.sh /tmp/manifest-submodulize-redundant.sh /tmp/plugin-submodules.manifest && chmod +x /tmp/submodulize.sh /tmp/manifest-submodulize-redundant.sh && chown www-data:www-data /tmp/submodulize.sh /tmp/manifest-submodulize-redundant.sh /tmp/plugin-submodules.manifest'
  submod_docker_env=(-u www-data)
  if [ -n "$SUBMOD_GIT_TOKEN" ]; then
    submod_docker_env+=(-e "GITHUB_TOKEN=${SUBMOD_GIT_TOKEN}")
  fi
  if [ "${SUBMODULIZE_SSH:-}" = "1" ]; then
    submod_docker_env+=(-e "SUBMODULIZE_USE_SSH=1")
  fi
  MSYS_NO_PATHCONV=1 docker exec "${submod_docker_env[@]}" "${NAME}-moodle" bash -c '
    set -euo pipefail
    cd /var/www/html
    git config --add safe.directory /var/www/html
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      git config --local url."https://smatts3%40lsu.edu:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
    fi
    rm -rf blocks/ues_people
    git fetch origin MOODLE_405_MAIN
    git merge origin/MOODLE_405_MAIN
    git ls-files blocks/ues_people | xargs -r git update-index --skip-worktree
    rm -rf blocks/ues_people
    cp /tmp/plugin-submodules.manifest /var/www/html/plugin-submodules.manifest
    SMF="--no-commit"
    if [ "${SUBMODULIZE_USE_SSH:-}" = "1" ]; then SMF="$SMF --ssh"; fi
    if bash /tmp/manifest-submodulize-redundant.sh --repo /var/www/html; then
      echo "new.sh: All manifest plugin paths are already submodules; skipping submodulize.sh."
    else
      bash /tmp/submodulize.sh --no-replay --repo /var/www/html $SMF
    fi
    git update-index --skip-worktree config.php
  '
else
  # Pass GITHUB_TOKEN into the container so the fetch against the private
  # lsuonline/moodleus can authenticate. Once set, `git config --local
  # url...insteadOf` writes the rewrite into /var/www/html/.git/config so
  # subsequent in-container git operations (e.g. moodle-pull) work without
  # re-supplying the token.
  MSYS_NO_PATHCONV=1 docker exec -u www-data -e "GITHUB_TOKEN=${GITHUB_TOKEN:-}" "${NAME}-moodle" sh -c '
    set -e
    cd /var/www/html
    git config --add safe.directory /var/www/html
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      git config --local url."https://smatts3%40lsu.edu:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
    fi
    rm -rf blocks/ues_people
    git fetch origin MOODLE_405_MAIN
    git merge origin/MOODLE_405_MAIN
    git ls-files blocks/ues_people | xargs -r git update-index --skip-worktree
    rm -rf blocks/ues_people
    git update-index --skip-worktree config.php
  '
fi

# Root: use moodle-pull as git pull (handles merge + blocks/ues_people like above).
MSYS_NO_PATHCONV=1 docker exec "${NAME}-moodle" sh -c '
  git config --global alias.pull "!/usr/local/bin/moodle-pull"
'

# Use Traefik hostname for stable URL (survives container restarts)
URL="http://moodle.${NAME}.localhost"

if [ "$SKIP_INSTALL" = false ]; then
    echo "Waiting for database to come online... "
    sleep 5 & spinner $!

    echo "Running Moodle CLI installation... "

    # Remove config.php if present (e.g. from repo or previous run) so install can run cleanly.
    docker exec "${NAME}-moodle" rm -f /var/www/html/config.php 2>/dev/null || true

    # Fill in config form defaults. Adapt as needed for your environment.
    CFG_DBHOST="db"
    CFG_DBNAME="moodle"
    CFG_DBUSER="moodleuser"
    CFG_DBPASS="moodlepass"
    CFG_DBTYPE="mariadb"
    CFG_WWWROOT="${URL}"
    CFG_LANG="en"
    CFG_DATAROOT="/var/www/moodledata"
    CFG_PREFIX="mdl_"
    CFG_ADMINUSER="admin"
    CFG_ADMINPASS="Password1!"
    CFG_ADMINEMAIL="admin@example.com"
    CFG_FULLNAME="LSU Online Moodle (test)"
    CFG_SHORTNAME="LSU Online (test)"
    CFG_SUPPORTEMAIL="admin@example.com"

    # Run Moodle CLI installation (rm -f config.php again right before so nothing can have recreated it)
    MSYS_NO_PATHCONV=1 docker exec -u www-data "${NAME}-moodle" sh -c "rm -f /var/www/html/config.php && php /var/www/html/admin/cli/install.php \
        --non-interactive \
        --agree-license \
        --allow-unstable \
        --lang=\"${CFG_LANG}\" \
        --wwwroot=\"${CFG_WWWROOT}\" \
        --dataroot=\"${CFG_DATAROOT}\" \
        --dbtype=\"${CFG_DBTYPE}\" \
        --dbhost=\"${CFG_DBHOST}\" \
        --dbname=\"${CFG_DBNAME}\" \
        --dbuser=\"${CFG_DBUSER}\" \
        --dbpass=\"${CFG_DBPASS}\" \
        --prefix=\"${CFG_PREFIX}\" \
        --fullname=\"${CFG_FULLNAME}\" \
        --shortname=\"${CFG_SHORTNAME}\" \
        --adminuser=\"${CFG_ADMINUSER}\" \
        --adminpass=\"${CFG_ADMINPASS}\" \
        --adminemail=\"${CFG_ADMINEMAIL}\" \
        --supportemail=\"${CFG_SUPPORTEMAIL}\"" &
    spinner $!
    INSTALL_EXIT=$?
    if [ "$INSTALL_EXIT" -ne 0 ]; then
        echo -e "\nMoodle installation failed (exit code $INSTALL_EXIT). Stopping." >&2
        exit 1
    fi

    echo -e "\nMoodle installation complete!"
else
    echo "Skipping Moodle installation: --skip flag provided."
fi

# Set misc config values (component|name|value format, use - for core settings)
echo "Setting up theme and config... "
while IFS='|' read -r component name value; do
    [[ -z "$name" || "$name" =~ ^# ]] && continue
    # Trim trailing whitespace/newlines from value
    value="${value%%[[:space:]]}"
    set_config "$component" "$name" "$value"
done <<'EOF'
-|bccaddress|${CFG_SUPPORTEMAIL}
-|theme|snap
theme_snap|themecolor|#461d7c
theme_snap|fullname|Welcome to LSU Moodle (test)!
theme_snap|subtitle|Louisiana State University (test)
theme_snap|headingfont|Roboto
block_backadel|path|/storage/
enrol_workdaystudent|apiversion|43.0
enrol_workdaystudent|campus|AU00000079
enrol_workdaystudent|campusname|LSUAM
enrol_workdaystudent|brange|60
enrol_workdaystudent|erange|0
enrol_workdaystudent|autoparent|0
enrol_workdaystudent|parentcat|
enrol_workdaystudent|primaryrole|
enrol_workdaystudent|nonprimaryrole|
enrol_workdaystudent|studentrole|
enrol_workdaystudent|unenroll|
enrol_workdaystudent|numberthreshold|10000
enrol_workdaystudent|createprior|60
enrol_workdaystudent|enrollprior|60
enrol_workdaystudent|visible|0
enrol_workdaystudent|course_grouping|0
enrol_workdaystudent|suspend|0
enrol_workdaystudent|namingformat|WDS - {period_year} {period_type} {course_subject_abbreviation} {course_number} for {firstname} {lastname} {delivery_mode}
enrol_workdaystudent|contacts|rrusso@lsu.edu
EOF

#Set confidential config values from ./confidential
if [ -f "./confidential" ]; then
    echo "Setting confidential config values... "
    while IFS='|' read -r component name value; do
        [[ -z "$name" || "$name" =~ ^# ]] && continue
        # Trim trailing whitespace/newlines from value
        value="${value%%[[:space:]]}"
        set_config "$component" "$name" "$value" true
    done < ./confidential
else
    echo "No confidential config values found. Skipping..."
fi

#Set custom CSS (if config/custom.css exists and is not empty)
echo "Setting custom CSS... "
CUSTOM_CSS_FILE="$(dirname "$0")/config/custom.css"
if [ -s "$CUSTOM_CSS_FILE" ]; then
    # Copy CSS file to container and set via PHP (file too large for command line arg)
    MSYS_NO_PATHCONV=1 docker cp -q "$(host_path_for_docker_cp "$CUSTOM_CSS_FILE")" "${NAME}-moodle:/tmp/custom.css" && \
    MSYS_NO_PATHCONV=1 docker exec -u www-data "${NAME}-moodle" php -r "
        define('CLI_SCRIPT', true);
        require('/var/www/html/config.php');
        \$css = file_get_contents('/tmp/custom.css');
        set_config('customcss', \$css, 'theme_snap');
    " && \
    MSYS_NO_PATHCONV=1 docker exec "${NAME}-moodle" rm /tmp/custom.css & spinner $!
fi

# Set site_is_public to false in config.php using sed to insert the line before the require_once line.
echo "Setting \$CFG->site_is_public = false in config.php..."
MSYS_NO_PATHCONV=1 docker exec "${NAME}-moodle" sed -i "/require_once/s/^/\$CFG->site_is_public = false;\n/" /var/www/html/config.php


# Set git username and email based on the user's system
echo "Setting git username and email... "
MSYS_NO_PATHCONV=1 docker exec "${NAME}-moodle" git config --global user.name "$(git config --global user.name)"
MSYS_NO_PATHCONV=1 docker exec "${NAME}-moodle" git config --global user.email "$(git config --global user.email)"

echo ""
echo "A new LSU Online Moodle dev environment ($NAME) is up and running."
echo ""
echo "Moodle: "
LOGIN_URL="$URL/login/index.php?loginredirect=1&username=${CFG_ADMINUSER}"
printf '\e]8;;%s\a%s\e]8;;\a\n' "$LOGIN_URL" "$URL" 
printf '\nAdmin username: %s\nAdmin password: %s\n' "${CFG_ADMINUSER}" "${CFG_ADMINPASS}"
echo ""
echo "phpMyAdmin: "
printf '\e]8;;%s\a%s\e]8;;\a\n' "http://phpmyadmin.${NAME}.localhost" "http://phpmyadmin.${NAME}.localhost"

echo -e "\nWhen you're done, you can stop the environment with: 
docker compose -p ${NAME} down"
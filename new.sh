#!/usr/bin/env bash
set -euo pipefail

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

# Set a Moodle config value via CLI
# Usage: set_config [component] name value
#   - If component is empty or "-", sets a core config
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
        MSYS_NO_PATHCONV=1 docker exec -u www-data "${NAME}-web-1" php /var/www/html/admin/cli/cfg.php \
            --name="$name" \
            --set="$value" \
            & spinner $!
    else
        MSYS_NO_PATHCONV=1 docker exec -u www-data "${NAME}-web-1" php /var/www/html/admin/cli/cfg.php \
            --component="$component" \
            --name="$name" \
            --set="$value" \
            & spinner $!
    fi
}

SKIP_INSTALL=false
NAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: new.sh [OPTION]... [NAME]
    Creates a new dev environment named NAME (or random if not provided).
    Options:
        -h --help   Shows this text.
        -s --skip   Skip automatic Moodle installation.";
            exit;
            ;;
        -s|--skip)
            SKIP_INSTALL=true
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


BRANCH_NAME=$NAME docker compose -p "${NAME}" up -d

# Update the container with the latest code
MSYS_NO_PATHCONV=1 docker exec "${NAME}-web-1" git pull --autostash origin develop

#Figure out what port docker mapped to localhost
PORT=$(docker port "${NAME}-web-1" 80 | head -n1 | sed 's/.*://' | tr -d '\r')

# Inside the container, set the wwwroot config value to use localhost and the mapped port
MSYS_NO_PATHCONV=1 docker exec "${NAME}-web-1" bash -lc "echo \"${PORT}\" > /PUBLIC_PORT"
# This should be a link in some terminals.
URL="http://localhost:${PORT}"

if [ "$SKIP_INSTALL" = false ]; then
    echo "Waiting for database to come online."
    sleep 5 & spinner $!

    echo "Running Moodle CLI installation..."

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

    # Run Moodle CLI installation
    MSYS_NO_PATHCONV=1 docker exec -u www-data "${NAME}-web-1" php /var/www/html/admin/cli/install.php \
        --non-interactive \
        --agree-license \
        --allow-unstable \
        --lang="${CFG_LANG}" \
        --wwwroot="${CFG_WWWROOT}" \
        --dataroot="${CFG_DATAROOT}" \
        --dbtype="${CFG_DBTYPE}" \
        --dbhost="${CFG_DBHOST}" \
        --dbname="${CFG_DBNAME}" \
        --dbuser="${CFG_DBUSER}" \
        --dbpass="${CFG_DBPASS}" \
        --prefix="${CFG_PREFIX}" \
        --fullname="${CFG_FULLNAME}" \
        --shortname="${CFG_SHORTNAME}" \
        --adminuser="${CFG_ADMINUSER}" \
        --adminpass="${CFG_ADMINPASS}" \
        --adminemail="${CFG_ADMINEMAIL}" \
        --supportemail="${CFG_SUPPORTEMAIL}" \
        2>/dev/null &
    spinner $!

    echo -e "\nMoodle installation complete!"
else
    echo "Skipping Moodle installation: --skip flag provided."
fi

# Set misc config values (component|name|value format, use - for core settings)
echo "Setting up theme and config..."
while IFS='|' read -r component name value; do
    [[ -z "$name" || "$name" =~ ^# ]] && continue
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
while IFS='|' read -r component name value; do
    [[ -z "$name" || "$name" =~ ^# ]] && continue
    set_config "$component" "$name" "$value" true
done < ./confidential

#Set custom CSS (if config/custom.css exists and is not empty)
CUSTOM_CSS_FILE="$(dirname "$0")/config/custom.css"
if [ -s "$CUSTOM_CSS_FILE" ]; then
    # Copy CSS file to container and set via PHP (file too large for command line arg)
    MSYS_NO_PATHCONV=1 docker cp -q "$CUSTOM_CSS_FILE" "${NAME}-web-1:/tmp/custom.css" && \
    MSYS_NO_PATHCONV=1 docker exec -u www-data "${NAME}-web-1" php -r "
        define('CLI_SCRIPT', true);
        require('/var/www/html/config.php');
        \$css = file_get_contents('/tmp/custom.css');
        set_config('customcss', \$css, 'theme_snap');
    " && \
    MSYS_NO_PATHCONV=1 docker exec "${NAME}-web-1" rm /tmp/custom.css & spinner $!
fi

# Set git username and email based on the user's system.
MSYS_NO_PATHCONV=1 docker exec "${NAME}-web-1" git config --global user.name "$(git config --global user.name)"
MSYS_NO_PATHCONV=1 docker exec "${NAME}-web-1" git config --global user.email "$(git config --global user.email)"

echo ""
echo "A new LSU Online Moodle dev environment ($NAME) is up and running. Log in here: "
LOGIN_URL="$URL/login/index.php?loginredirect=1&username=${CFG_ADMINUSER}"
printf '\e]8;;%s\a%s\e]8;;\a\n' "$LOGIN_URL" "$LOGIN_URL" 
printf '\nAdmin username: %s\nAdmin password: %s\n' "${CFG_ADMINUSER}" "${CFG_ADMINPASS}"

echo -e "\nWhen you're done, you can stop the environment with: 
docker compose -p ${NAME} down"
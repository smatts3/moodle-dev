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
    cursorBack
    echo -en "\r\n"

    return $?
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

    echo -e "\nInstallation complete!"
else
    echo "Skipping Moodle installation (--skip flag provided)."
fi

echo "Setting up theme..."

# Set theme to snap.
MSYS_NO_PATHCONV=1 docker exec -u www-data "${NAME}-web-1" php /var/www/html/admin/cli/cfg.php \
    --name=theme \
    --set=snap \
    & spinner $!

#Set snap colors to blue.
MSYS_NO_PATHCONV=1 docker exec -u www-data "${NAME}-web-1" php /var/www/html/admin/cli/cfg.php \
    --component=theme_snap \
    --name="themecolor" \
    --set="#461d7c" \
    & spinner $!

#Set site name
MSYS_NO_PATHCONV=1 docker exec -u www-data "${NAME}-web-1" php /var/www/html/admin/cli/cfg.php \
    --component=theme_snap \
    --name=fullname \
    --set="Welcome to LSU Moodle (test)!" \
    & spinner $!

#Set site description
MSYS_NO_PATHCONV=1 docker exec -u www-data "${NAME}-web-1" php /var/www/html/admin/cli/cfg.php \
    --component=theme_snap \
    --name=subtitle \
    --set="Louisiana State University (test)" \
    & spinner $!

#Set font to Roboto
MSYS_NO_PATHCONV=1 docker exec -u www-data "${NAME}-web-1" php /var/www/html/admin/cli/cfg.php \
    --component=theme_snap \
    --name=headingfont \
    --set="Roboto" \
    & spinner $!

#Set custom CSS (if config/custom.css exists and is not empty)
CUSTOM_CSS_FILE="$(dirname "$0")/config/custom.css"
if [ -s "$CUSTOM_CSS_FILE" ]; then
    # Copy CSS file to container and set via PHP (file too large for command line arg)
    MSYS_NO_PATHCONV=1 docker cp -q "$CUSTOM_CSS_FILE" "${NAME}-web-1:/tmp/custom.css"
    MSYS_NO_PATHCONV=1 docker exec -u www-data "${NAME}-web-1" php -r "
        define('CLI_SCRIPT', true);
        require('/var/www/html/config.php');
        \$css = file_get_contents('/tmp/custom.css');
        set_config('customcss', \$css, 'theme_snap');
    "
    MSYS_NO_PATHCONV=1 docker exec "${NAME}-web-1" rm /tmp/custom.css
fi

echo ""
echo "A new LSU Online Moodle dev environment ($NAME) is up and running. Log in here: "
LOGIN_URL="$URL/login/index.php"
printf '\e]8;;%s\a%s\e]8;;\a\n' "$LOGIN_URL" "$LOGIN_URL" 
printf '\nAdmin username: %s\nAdmin password: %s\n' "${CFG_ADMINUSER}" "${CFG_ADMINPASS}"
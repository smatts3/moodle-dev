#!/usr/bin/env bash
set -euo pipefail

function cursorBack() {
  echo -en "\033[$1D"
  # Mac compatible, but goes back to first column always. See comments
  #echo -en "\r"
}

function spinner() {
    # make sure we use non-unicode character type locale 
    # (that way it works for any locale as long as the font supports the characters)
    local LC_CTYPE=C

    local pid=$1 # Process Id of the previous running command
    # local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    # local spin='⠁⠉⠙⠹⠽⠿⠾⠶⠦⠆⠂⠀'
    local spin='⠁⠉⠙⠹⠽⠾⠷⠯⠟⠻⠽⠾⠶⠦⠆⠂⠀'
    local charwidth=3

    local i=0
    tput civis # cursor invisible
    while kill -0 $pid 2>/dev/null; do
        local i=$(((i + $charwidth) % ${#spin}))
        printf "%s" "${spin:$i:$charwidth}"

        cursorBack 1
        sleep .016
    done
    tput cnorm
    wait $pid # capture exit code
    return $?
}

function extract_sesskey() {
    html=$1
    return ''
}

if [ $# -eq 1 ]; then
    if [[ $1 == "-h" || $1 == "--help" ]]; then
        echo "Usage: new.sh [OPTION]... [NAME]
    Creates a new dev environment named NAME (or random if not provided).
    Options:
        -h --help   Shows this text.
        -s --skip   Skip automatic Moodle installation.";
        exit;
    fi
    NAME=$1
else
    #Otherwise use a random project name
    NAME=$(dd if=/dev/urandom bs=2 count=1 2>/dev/null | od -An -t x1 | tr -d ' \n')
fi


BRANCH_NAME=$NAME docker compose -p "${NAME}" up -d
# docker network connect traefik $NAME-web-1

#Figure out what port docker mapped to localhost
PORT=$(docker port "${NAME}-web-1" 80 | head -n1 | sed 's/.*://' | tr -d '\r')

# Inside the container, set the wwwroot config value to use localhost and the mapped port
# MSYS_NO_PATHCONV=1 docker exec "${NAME}-web-1" bash -lc "sed -Ei \"s|localhost:8080|localhost:${PORT}|g\" /var/www/html/config.php"
MSYS_NO_PATHCONV=1 docker exec "${NAME}-web-1" bash -lc "echo \"${PORT}\" > /PUBLIC_PORT"

echo "A new LSU Online Moodle dev environment is up and running! Access it at: "
# This should be a link in some terminals.
URL="http://localhost:${PORT}"
#printf '\033]8;;http://localhost:%s\033\\http://localhost:%s\033]8;;\033\\\n' "$PORT" "$PORT"

echo "Waiting for database to come online."
sleep 5 & spinner $!

printf '\e]8;;%s\a%s\e]8;;\a\n' "$URL" "$URL"

# echo "Running installation."
# BASE_URL="http://localhost:${PORT}"

# mkdir -p cookies
# touch cookies/$NAME
# # Do fill first page.
# exec 3< <(curl -Lsc cookies/$NAME -b cookies/$NAME "${BASE_URL}/admin/index.php?cache=0&agreelicense=1&confirmrelease=1&lang=en" \
#     | grep sesskey \
#     | sed -n 's/.*"sesskey":"\([^"]*\)".*/\1/p')
# spinner "$!"

# read -r sesskey <&3

# exec 3>&-

# echo "Grabbing sesskey. $sesskey"

# sesskey=$(curl -Lsc cookies/$NAME -b cookies/$NAME "${BASE_URL}/user/editadvanced.php?id=2" \
#     | grep sesskey \
#     | sed 's/.*"sesskey":"\([^"]*\)".*/\1/p' -n )

# echo "Setting up admin user. $sesskey"
# # Do second page.
# exec 3< <(curl -Lsc cookies/$NAME -b cookies/$NAME \
# -o responses/$NAME.html \
# --location "${BASE_URL}/user/editadvanced.php" \
# -X POST \
# --header 'Content-Type: application/x-www-form-urlencoded' \
# --header "Origin: ${BASE_URL}" \
# --header "Referer: ${BASE_URL}/user/editadvanced.php?id=2" \
# --data-urlencode 'course=1' \
# --data-urlencode 'returnto=' \
# --data-urlencode "sesskey=$sesskey" \
# --data-urlencode 'username=admin' \
# --data-urlencode 'newpassword=Password1!' \
# --data-urlencode 'firstname=Admin' \
# --data-urlencode 'lastname=User' \
# --data-urlencode 'email=blah@blah.com' \
# --data-urlencode 'maildisplay=1' \
# --data-urlencode 'timezone=99' \
# --data-urlencode 'submitbutton=Update profile' \
#     | grep sesskey \
#     | sed -n 's/.*"sesskey":"\([^"]*\)".*/\1/p')
# spinner "$!"

# read -r sesskey <&3
# exec 3>&-

# sleep 1

# echo "Setting up admin user. $sesskey"
# # Do second page.
# exec 3< <(curl -Lsc cookies/$NAME -b cookies/$NAME \
# -o responses/$NAME.html \
# --location "${BASE_URL}/user/editadvanced.php" \
# -X POST \
# --header 'Content-Type: application/x-www-form-urlencoded' \
# --header "Origin: ${BASE_URL}" \
# --header "Referer: ${BASE_URL}/user/editadvanced.php?id=2" \
# --data-urlencode 'course=1' \
# --data-urlencode 'returnto=' \
# --data-urlencode "sesskey=$sesskey" \
# --data-urlencode 'username=admin' \
# --data-urlencode 'newpassword=Password1!' \
# --data-urlencode 'firstname=Admin' \
# --data-urlencode 'lastname=User' \
# --data-urlencode 'email=blah@blah.com' \
# --data-urlencode 'maildisplay=1' \
# --data-urlencode 'timezone=99' \
# --data-urlencode 'submitbutton=Update profile' \
#     | grep sesskey \
#     | sed -n 's/.*"sesskey":"\([^"]*\)".*/\1/p')
# spinner "$!"

# read -r sesskey <&3
# exec 3>&-

# curl -Lsc cookies/$NAME --location "${BASE_URL}/admin" \
# & spinner $! 
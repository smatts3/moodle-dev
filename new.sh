#!/usr/bin/env bash
set -euo pipefail

if [ $# -eq 1 ]; then
    NAME=$1
else
    #Otherwise use a random project name
    NAME=$(dd if=/dev/urandom bs=2 count=1 2>/dev/null | od -An -t x1 | tr -d ' \n')
fi

docker compose -p "${NAME}" up -d

#Figure out what port docker mapped to localhost
PORT=$(docker port "${NAME}-web-1" 80 | head -n1 | sed 's/.*://' | tr -d '\r')

# Inside the container, set the wwwroot config value to use localhost and the mapped port
MSYS_NO_PATHCONV=1 docker exec "${NAME}-web-1" bash -lc "sed -Ei \"s|localhost:8080|localhost:${PORT}|g\" /var/www/html/config.php"

echo "A new LSU Online Moodle dev environment is up and running! Access it at: "
printf '\033]8;;http://localhost:%s\033\\http://localhost:%s\033]8;;\033\\\n' "$PORT" "$PORT"
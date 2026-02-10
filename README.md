# LSU Moodle dev / test environment
This will create a docker stack for LSU's moodle for you to access locally and develop / test in.

# Requirements

UNIX environment, Linux / Mac preferred.

## Linux / MacOS

- Docker
- Docker Compose 

## Windows
- Docker Desktop (or docker / docker compose)
- Git Bash (or MINGW)

# Setup

Put confidential moodle / plugin config settings into `./confidential`.

The format is `COMPONENT`|`NAME`|`VALUE`. One per line. See `confidential.template`.

# Usage

On Windows, make sure docker desktop is running. 

1. To launch a new instance of a dev environment, in a bash terminal run:

		new.sh [NAME]
	
	Where NAME is an optional branch name (eg. new_widget, fix_login)

	If NAME isn't supplied, a random 4 character name will be chosen (eg. e92d)

1. If successful, you can access the site at http://moodle.NAME.localhost

1. You can use a terminal within the container by doing:

		MSYS_NO_PATHCONV=1 docker exec -it {NAME}-moodle /bin/bash

1. You can edit code using VSCode with the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension and opening /var/www/html

1. Use git within the container itself

1. When done, clean up the stack with:

		docker compose -p {NAME} down

	Or you can delete the stack in docker desktop.

# Build

You probably won't need to build. Images by default are pulled from docker hub (or soon from a private repo). To generate a new build image do:

	docker build -t lsuonline/moodle-dev:latest .

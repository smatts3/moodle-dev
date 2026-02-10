# LSU Moodle dev / test environment
This will create a docker stack for LSU's moodle for you to access locally and develop / test in.

# Requirements

## Linux / MacOS

- Docker
- Docker Compose 

## Windows
- Docker Desktop (or docker / docker compose)
- Git Bash (or MINGW)

# Setup

Put confidential moodle / plugin config settings into `./confidential`.

The format is `COMPONENT`|`NAME`|`VALUE`. One per line. See `confidential.template`.

# Running

To launch a new instance of a dev environment run:

	new.sh [NAME]
	
Where NAME is an optional branch name (eg. new_widget, fix_login)

If NAME isn't supplied, a random 4 character name will be chosen (eg. e92d)

If successful, you can access the site at http://moodle.NAME.localhost

# Build (you probably won't need to)

Images by default are pulled from docker hub (or soon from a private repo). To generate a new build image do:

	docker build -t lsuonline/moodle-dev:latest .

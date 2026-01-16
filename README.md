Put confidential config settings into ./confidential in the format `COMPONENT`|`NAME`|`VALUE`. One per line. See `confidential.template` for examples.

To launch a new instance of a dev environment run, specifying an optional project name:

	new.sh [NAME]

To generate a new build image do:

	docker build -t lsuonline/moodle-dev:latest .

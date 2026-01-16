#!/bin/sh

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")";
cd $SCRIPT_DIR;
docker build -t lsuonline/moodle-dev:latest "$@" .
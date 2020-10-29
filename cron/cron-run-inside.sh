#!/bin/bash

exec 2>&1
set -e

# Cron's path tends to suck
export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:$HOME/bin:$HOME/.local/bin

# This is much less simple than usual because we're in a subdir
maindir="$(readlink -f "$(dirname "$0")"/..)"
lbcsdir="$(realpath "$(dirname "$(readlink -f "$0")")"/..)"

. $lbcsdir/config
. $maindir/config

$CONTAINER_BIN exec -it "$@"

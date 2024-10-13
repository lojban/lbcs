#!/bin/bash

# Error trapping from https://gist.github.com/oldratlee/902ad9a398affca37bfcfab64612e7d1
__error_trapper() {
  local parent_lineno="$1"
  local code="$2"
  local commands="$3"
  echo "error exit status $code, at file $0 on or near line $parent_lineno: $commands"
}
trap '__error_trapper "${LINENO}/${BASH_LINENO}" "$?" "$BASH_COMMAND"' ERR

set -euE -o pipefail
shopt -s failglob

maindir="$(readlink -f "$(dirname "$0")")"
lbcsdir="$(dirname "$(readlink -f "$0")")"

if [[ ! $1 ]]
then
    echo "Need container name as first argument."
    exit 1
fi

if [[ ! $2 ]]
then
    echo "Need addon name as second argument."
    exit 1
fi

container="$1"
containerdir="$maindir/containers/$container"
addon="$2"
addondir="$containerdir/addons/$addon"

set -o nounset

if [[ ! -d $containerdir ]]
then
    echo "Can't find container dir $containerdir"
    exit 1
fi

if [[ ! -d $addondir ]]
then
    echo "Can't find addon dir $addondir"
    exit 1
fi

# Make shellcheck happy
name=''
run_program=''

# shellcheck disable=SC1091
. "$lbcsdir/config"
# shellcheck disable=SC1091
. "$maindir/config"
if [[ -f $maindir/secrets ]]
then
    # shellcheck disable=SC1091
    . "$maindir/secrets"
fi
# shellcheck disable=SC1091
. "$containerdir/config"
if [[ -f $containerdir/secrets ]]
then
    # shellcheck disable=SC1091
    . "$containerdir/secrets"
fi
# shellcheck disable=SC1091
. "$addondir/config"
if [[ -f $addondir/secrets ]]
then
    # shellcheck disable=SC1091
    . "$addondir/secrets"
fi

if [[ ! ${bundle-} ]]
then
    echo "No bundle name (tag 'bundle') found in $maindir/config  ; please set.  (Used to be called 'service'.)"
    exit 1
fi

if [[ $bundle = "$name" ]]
then
    echo "The bundle name ($bundle) and the addon name ($name) can't be the same; modify one of the config files to fix please."
    exit 1
fi

if [[ ${stop_program-} ]]
then
    echo -e "\nStopping addon $name for container $container in bundle $bundle\n"

    # Need the eval to expand variables in $run_args itself; probably a better way
    # to do this but meh
    eval "$CONTAINER_BIN" exec -it "$container" "$run_program" 2>&1

    sleep 5
fi

if [[ ${kill_string-} ]]
then
    echo -e "\nStopping addon $name for container $container in bundle $bundle by killing processes that look like '$kill_string'\n"

    # shellcheck disable=SC2034
    for num in $(seq 1 10)
    do
        if ! "$CONTAINER_BIN" exec web pgrep -f "$kill_string" >/dev/null 2>&1
        then
            break
        fi

        "$CONTAINER_BIN" exec web pkill -f "$kill_string" || true
        sleep 1
        "$CONTAINER_BIN" exec web pkill -9 -f "$kill_string" || true
    done

    "$CONTAINER_BIN" exec web pgrep -f "$kill_string" >/dev/null 2>&1 || exit 0
fi

if [[ -z ${stop_program-} && -z ${kill_string-} ]]
then
    echo -e "\nAddon $name for container $container in bundle $bundle has no stop_program or kill_string!  Can't stop it!\n"
fi

echo "Addon $name for container $container in bundle $bundle is stopped"

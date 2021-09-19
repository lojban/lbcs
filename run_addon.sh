#!/bin/bash

exec 2>&1
set -o errexit
set -o errtrace
set -o pipefail

trap 'echo -e "\n\nExited due to script error! Exit value: $?\n\n"' ERR

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

if [[ ! $bundle ]]
then
    echo "No bundle name (tag 'bundle') found in $maindir/config  ; please set.  (Used to be called 'service'.)"
    exit 1
fi

if [[ $bundle = "$name" ]]
then
    echo "The bundle name ($bundle) and the addon name ($name) can't be the same; modify one of the config files to fix please."
    exit 1
fi

if [[ ! $run_program ]]
then
    echo "No addon run program (tag 'run_program') found in $addondir/config ; there's no point in having an addon without one."
    exit 1
fi

after_containers="$after_containers $container"

for after_container in $after_containers
do
    # shellcheck disable=SC2034
    for num in $(seq 1 60)
    do
        if [[ $($CONTAINER_BIN container inspect --format '{{.State.Status}}' "$after_container") == 'running' ]]
        then
            break
        fi
        echo -e "\nWaiting for required container $after_container to start.\n"
        sleep 5
    done

    if [[ $($CONTAINER_BIN container inspect --format '{{.State.Status}}' "$after_container") == 'running' ]]
    then
        echo -e "\nRequired container $after_container has started.\n"
    else
        echo -e "\nRequired container $after_container has not started; exiting.\n"
        exit 1
    fi
done

if [[ $files_to_erb_on_run ]]
then
    echo -e "\nERBing runtime files\n"

    for file in $files_to_erb_on_run
    do
        echo "ERBing $maindir/$file.erb to $maindir/$file"
        "$lbcsdir/lbcserb" "$maindir" "$lbcsdir" "$container" "$maindir/$file.erb" "$maindir/$file" addon "$addon"
    done
fi

if [[ $run_pre_script ]]
then
    echo -e "\nRunning pre-script for addon $addon in container $container\n"
    bash -c "$(eval "$run_pre_script")"
    echo -e "\nDone running pre-script for addon $addon in container $container\n"
fi

echo -e "\nRunning addon $name for container $container in bundle $bundle\n"

# Need the eval to expand variables in $run_args itself; probably a better way
# to do this but meh
eval "$CONTAINER_BIN" exec -it "$container" "$run_program" 2>&1

if [[ $run_post_script ]]
then
    echo -e "\nRunning post-script for addon $addon in container $container\n"
    bash -c "$(eval "$run_post_script")"
    echo -e "\nDone running post-script for addon $addon in container $container\n"
fi

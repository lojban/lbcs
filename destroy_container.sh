#!/bin/bash

exec 2>&1
set -e

maindir="$(readlink -f "$(dirname "$0")")"
lbcsdir="$(dirname "$(readlink -f "$0")")"

container="$1"
containerdir="$maindir/containers/$container"

if [[ ! $container ]]
then
    echo "Need container name as single argument."
    exit 1
fi

if [[ ! -d $containerdir ]]
then
    echo "Can't find container dir $containerdir"
    exit 1
fi

. $lbcsdir/config
. $maindir/config
. $containerdir/config

status="$(podman ps -a -f name=$name --format '{{.ID}} {{.Status}}')"

# If it's up, try to kill it
pat='^[0-9a-f][0-9a-f]* Up'
if [[ $status =~ $pat ]]
then
    echo -e "\nTrying to stop container $name\n"
    $CONTAINER_BIN stop --time=30 $name || true
    echo -e "\nTrying to kill container $name\n"
    $CONTAINER_BIN kill $name || true
fi

# If it exists at all, try to remove it
if [[ $status ]]
then
    echo -e "\nTrying to delete container $name\n"
    $CONTAINER_BIN rm $name || true
fi

if [[ $(podman ps -a -f name=$name --format '{{.ID}} {{.Status}}' | wc -l) -eq 0 ]]
then
    echo -e "\nContainer $name stopped and removed\n"
    exit 0
else
    echo -e "\nContainer $name still seems to be around; this is bad\n"
    exit 1
fi

echo 'How did we get here??'
exit 99

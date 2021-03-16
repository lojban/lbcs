#!/bin/bash

shopt -s nullglob

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

if [[ ! $version ]]
then
    echo "No version (tag 'version') found in $containerdir/config ; please set. You can increment the version to force a rebuild of the docker container."
    exit 1
fi

if [[ ! $service ]]
then
    echo "No service name (tag 'service') found in $maindir/config  ; please set."
    exit 1
fi

for file in $maindir/misc/*.erb
do
    echo -e "\nERBing misc (build-time) files: $file\n" 

    $lbcsdir/lbcserb $maindir $lbcsdir $container "$file" "$( echo "$file" | sed 's/\.erb$//')" containers userid=$(id -u) groupid=$(id -g)
done

mkdir -p $containerdir/tmp

$lbcsdir/lbcserb $maindir $lbcsdir $container $containerdir/Dockerfile.erb $containerdir/tmp/Dockerfile.$$ containers userid=$(id -u) groupid=$(id -g)

cd $maindir

$CONTAINER_BIN build -t $(id -un)/$service-$container:$version --quiet=false -f $containerdir/tmp/Dockerfile.$$ .

if [[ $? -ne 0 ]]
then
    echo "Docker build failed."
    exit 1
fi

rm -rf $containerdir/tmp

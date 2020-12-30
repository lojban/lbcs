#!/bin/bash

# This is often called from cron, so:
export PATH=$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:$PATH

exec 2>&1
set -e

maindir="$(readlink -f "$(dirname "$0")")"
lbcsdir="$(dirname "$(readlink -f "$0")")"

containerdir="$maindir/containers/$container"

if [[ ! -d $containerdir ]]
then
    echo "Can't find container dir $containerdir"
    exit 1
fi

. $lbcsdir/config
. $maindir/config

cd $containerdir

for name in *
do
    echo -e "\n\nRebuilding image for container $name\n\n"
    $maindir/build_image.sh $name
done

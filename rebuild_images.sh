#!/bin/bash

# This is often called from cron, so:
export PATH=$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:$PATH

exec 2>&1
set -o errexit
set -o nounset
set -o pipefail

maindir="$(readlink -f "$(dirname "$0")")"
lbcsdir="$(dirname "$(readlink -f "$0")")"

# shellcheck disable=SC1091
. "$lbcsdir/config"
# shellcheck disable=SC1091
. "$maindir/config"

cd "$maindir/containers/"

for name in *
do
    echo -e "\n\nRebuilding image for container $name\n\n"
    "$maindir/build_image.sh" "$name"
done

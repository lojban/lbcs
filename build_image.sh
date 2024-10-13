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

exec 2>&1

maindir="$(readlink -f "$(dirname "$0")")"
lbcsdir="$(dirname "$(readlink -f "$0")")"

if [[ ! ${1-} ]]
then
    echo "Need container name as single argument."
    exit 1
fi

container="${1-}"
containerdir="$maindir/containers/$container"

if [[ ! -d $containerdir ]]
then
    echo "Can't find container dir $containerdir"
    exit 1
fi

# shellcheck disable=SC1091
. "$lbcsdir/config"
# shellcheck disable=SC1091
. "$maindir/config"
# shellcheck disable=SC1091
. "$containerdir/config"

if [[ ! $version ]]
then
    echo "No version (tag 'version') found in $containerdir/config ; please set. You can increment the version to force a rebuild of the docker container."
    exit 1
fi

if [[ ! $bundle ]]
then
    echo "No bundle name (tag 'bundle') found in $maindir/config  ; please set.  (Used to be called 'service'.)"
    exit 1
fi

# Use find here to avoid failglob
if [[ -d "$maindir/misc" ]]
then
    # shellcheck disable=SC2044
    for file in $(find "$maindir/misc" -name '*.erb')
    do
        echo -e "\nERBing misc (build-time) files: $file\n" 

        "$lbcsdir/lbcserb" "$maindir" "$lbcsdir" "$container" "$file" "${file%.erb}" container "userid=$(id -u)" "groupid=$(id -g)"
    done
fi

mkdir -p "$containerdir/tmp"

"$lbcsdir/lbcserb" "$maindir" "$lbcsdir" "$container" "$containerdir/Dockerfile.erb" "$containerdir/tmp/Dockerfile.$$" container "userid=$(id -u)" "groupid=$(id -g)"

cd "$maindir"

if ! $CONTAINER_BIN build -t "$(id -un)/$bundle-$container:$version" --quiet=false -f "$containerdir/tmp/Dockerfile.$$" .
then
    echo "Docker build failed."
    exit 1
fi

rm -rf "$containerdir/tmp"

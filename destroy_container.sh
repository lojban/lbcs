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

if [[ ! $1 ]]
then
    echo "Need container name as single argument."
    exit 1
fi

container="$1"
containerdir="$maindir/containers/$container"

set -o nounset

if [[ ! -d $containerdir ]]
then
    echo "Can't find container dir $containerdir"
    exit 1
fi

# Make shellcheck happy
name=''

# shellcheck disable=SC1091
. "$lbcsdir/config"
# shellcheck disable=SC1091
. "$maindir/config"
# shellcheck disable=SC1091
. "$containerdir/config"

status="$($CONTAINER_BIN ps -a -f name="^$name$" --format '{{.ID}} {{.Status}}')"

# If it's up, try to kill it
pat='^[0-9a-f][0-9a-f]* Up'
if [[ $status =~ $pat ]]
then
    echo -e "\nTrying to stop container $name\n"
    $CONTAINER_BIN stop --time=30 "$name" || true
    echo -e "\nTrying to kill container $name\n"
    $CONTAINER_BIN kill "$name" || true
fi

# If it exists at all, try to remove it
if [[ $status ]]
then
    echo -e "\nTrying to delete container $name\n"
    $CONTAINER_BIN rm "$name" || true
fi

if [[ $($CONTAINER_BIN ps -a -f name="^$name$" --format '{{.ID}} {{.Status}}' | wc -l) -eq 0 ]]
then
    echo -e "\nContainer $name stopped and removed\n"
    exit 0
else
    echo -e "\nContainer $name still seems to be around; this is bad\n"
    exit 1
fi

echo 'How did we get here??'
exit 99

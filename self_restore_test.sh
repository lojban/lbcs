#!/bin/bash

# Test restore of our backups; see the backup script for general
# notes.

exec 2>&1

if [[ ! ${1-} ]]
then
    echo "Need user@host for ssh as first argument."
    exit 1
fi

dest="$1"
shift

if [[ ! ${1-} ]]
then
    echo "Need email address for alerts as second argument."
    exit 1
fi

email="$1"
shift

# Error trapping from https://gist.github.com/oldratlee/902ad9a398affca37bfcfab64612e7d1
__error_trapper() {
  local parent_lineno="$1"
  local code="$2"
  local commands="$3"
  echo "error exit status $code, at file $0 on or near line $parent_lineno: $commands" | tee | mailx -s "**** RESTORE TEST FAILED FOR $(id -un)!!!" "$email"
}
trap '__error_trapper "${LINENO}/${BASH_LINENO}" "$?" "$BASH_COMMAND"' ERR

set -euE -o pipefail
shopt -s failglob

BACKUP_DIR="backups/$(id -un)"

echo
echo "Pulling test file from ${BACKUP_DIR}."

tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)

echo
echo
rsync -av "$dest:${BACKUP_DIR}/.rsync-restore-test-*" "$tmp_dir/"
echo
echo

backupdate="$(stat -c %y "$tmp_dir/" | sed 's/ .*//' | tr -d '-')"
restorefile="$tmp_dir/.rsync-restore-test-$backupdate"
restorefiledate="$(cat "$restorefile" || echo 'NO RESTORE TEST FILE FOUND')"

if [[ $backupdate = "$restorefiledate" ]]
then
  echo "Looks good; backup directory and test file both have dates of $backupdate."
  echo
else
  message="VERY BAD RESTORE TEST FAILED! Correct data not found!  File $restorefile should have '$backupdate' as its contents.  Bailing."
  (echo "$message" ; find "$tmp_dir/" -ls ; echo "restore file contents: $restorefiledate") | mailx -s "**** RESTORE TEST FAILED FOR $(id -un)!!!" "$email"
  (echo "$message" ; find "$tmp_dir/" -ls ; echo "restore file contents: $restorefiledate")
  exit 1
fi

rm -rf "${tmp_dir:?}/"

echo "Restore test completed successfully"

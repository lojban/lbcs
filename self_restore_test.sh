#!/bin/bash

# Test restore of our backups; see the backup script for general
# notes (although note that this script is 100% my creation).

exec 2>&1
set -o errexit
set -o errtrace
set -o pipefail
set -o nounset

trap 'exitval=$?
if [[ $exitval -ne 0 ]]
then
  echo -e "\n\nExited due to script error! Exit value: $exitval\n\n" | tee | mailx -s "**** RESTORE TEST FAILED FOR $(id -un)!!!" "$email"
fi' ERR EXIT

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

BACKUP_DIR="backups/$(id -un)"

# Get a count of all backups in the last 5 days
fivedaycount=$(ssh "$dest" find "${BACKUP_DIR}/" -depth 1 -mtime -5 | grep -cv '/latest$')

if [[ $fivedaycount -gt 2 ]]
then
  echo "We found $fivedaycount backups in the last 5 days."
else
  message="VERY BAD RESTORE TEST FAILED!  Only $fivedaycount backups found in the last five days for $(id -un)!"
  echo "$message" | mailx -s "**** RESTORE TEST FAILED FOR $(id -un)!!!" "$email"
  echo "$message"
  exit 1
fi

# NOTE: Best way I've found to get a timestamp from rsync.net: ls -l -c -D epoch=%s backups/spvlasisku/262

randombackup=$(ssh "$dest" find "${BACKUP_DIR}/" -depth 1 -mtime -5 | grep -v '/latest$' | shuf | head -n 1 | sed 's;.*/;;')

echo
echo "Pulling test file from random backup $randombackup."

tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)

echo
echo
rsync -av "$dest:${BACKUP_DIR}/$randombackup/.rsync-restore-test-*" "$tmp_dir/"
rsync -lptgod "$dest:${BACKUP_DIR}/$randombackup" "$tmp_dir/"
echo
echo

backupdate="$(stat -c %y "$tmp_dir/$randombackup" | sed 's/ .*//' | tr -d '-')"
restorefile="$tmp_dir/.rsync-restore-test-$backupdate"
restorefiledate="$(cat "$restorefile" || echo 'NO RESTORE TEST FILE FOUND')"

if [[ $backupdate = "$restorefiledate" ]]
then
  echo "Looks good; backup directory and test file both have dates of $backupdate."
  echo
else
  message="VERY BAD RESTORE TEST FAILED! Correct data not found!  File $restorefile in backup $randombackup should have '$backupdate' as its contents.  Bailing."
  (echo "$message" ; find "$tmp_dir/" -ls ; echo "restore file contents: $restorefiledate") | mailx -s "**** RESTORE TEST FAILED FOR $(id -un)!!!" "$email"
  (echo "$message" ; find "$tmp_dir/" -ls ; echo "restore file contents: $restorefiledate")
  exit 1
fi

rm -rf "${tmp_dir:?}/"

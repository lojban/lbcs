#!/bin/bash

# A script to perform incremental backups using rsync
#
# Originally taken from https://linuxconfig.org/how-to-create-incremental-backups-using-rsync-on-linux
#
# This and the restore script don't really fit the aesthetic of
# LBCS, but I wanted to run these backups on basically all of my
# LBCS setups, so here we are.
#
# Example use (in crontab):
#
#       # Daily backups
#       4 4 * * * <%= maindir %>/self_backup.sh account@account.rsync.net '+%j'
#
#       # Daily restore test
#       5 5 * * * <%= maindir %>/self_restore_test.sh account@account.rsync.net webmaster@lojban.org

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

if [[ ! ${1-} ]]
then
    echo "Need user@host for ssh as first argument."
    exit 1
fi

dest="$1"
shift

if [[ ! ${1-} ]]
then
    echo "Need date string (like '+%j') for backup schedule as second argument."
    exit 1
fi

datestr="$1"
shift

BACKUP_DIR="backups/$(id -un)"
DATETIME="$(date "$datestr")"
BACKUP_PATH="${BACKUP_DIR}/${DATETIME}"
LATEST_LINK="${BACKUP_DIR}/latest"

# Set up the restore test file
rm -f "$HOME"/.rsync-restore-test-*
date "+%Y%m%d" >"$HOME/.rsync-restore-test-$(date +%Y%m%d)"

# Get the host key -_-;
ssh -o StrictHostKeyChecking=no "$dest" 'uname -a' || true

echo -e "\n\nRunning rsync.\n\n"
set -x

ssh "$dest" mkdir -p "${BACKUP_DIR}"

date
rsync -a -SHA --delete \
  "$HOME/" \
  --link-dest "../latest" \
  --exclude=".cache" \
  --exclude=".local" \
  "$dest:${BACKUP_PATH}" || true
date

# shellcheck disable=SC2029
ssh "$dest" rm "${LATEST_LINK}" || true
ssh "$dest" ln -s "${DATETIME}" "${LATEST_LINK}"

echo "self_backup completed successfully"

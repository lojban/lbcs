#!/bin/bash

# Simple rsync backup, relies on the other end (i.e. rsync.net) for
# incremental snapshots.
#
# This and the restore script don't really fit the aesthetic of
# LBCS, but I wanted to run these backups on basically all of my
# LBCS setups, so here we are.
#
# Example use (in crontab):
#
#       # Daily backups
#       4 4 * * * <%= maindir %>/self_backup.sh account@account.rsync.net
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

maindir="$(readlink -f "$(dirname "$0")")"
lbcsdir="$(dirname "$(readlink -f "$0")")"

# shellcheck disable=SC1091
. "$lbcsdir/config"
# shellcheck disable=SC1091
. "$maindir/config"

BACKUP_DIR="backups/$(id -un)"

# Set up the restore test file
rm -f "$HOME"/.rsync-restore-test-*
date "+%Y%m%d" >"$HOME/.rsync-restore-test-$(date +%Y%m%d)"

# Get the host key -_-;
ssh -o StrictHostKeyChecking=no "$dest" 'uname -a' || true

echo -e "\n\nRunning rsync.\n\n"
set -x

ssh "$dest" mkdir -p "${BACKUP_DIR}"

date
rsync -v -a -SHA --delete --delete-excluded \
  "$HOME/" \
  --exclude=".cache" \
  --exclude=".local" \
  ${backup_extra_excludes:-} \
  "$dest:${BACKUP_DIR}/" || true
date

echo "self_backup completed successfully"

#!/bin/bash


exec 2>&1
set -e
set -x

CONTAINER_BIN=${CONTAINER_BIN:-$(which podman)}
CONTAINER_BIN=${CONTAINER_BIN:-$(which docker)}

./kill_database.sh 2>&1

hasterm=''
if tty -s
then
	hasterm='-t'
fi

#**************
# Database
#**************
# FOR TESTING; forces complete container rebuild
cd dockerfiles/
# $CONTAINER_BIN build --no-cache -t jbotcan/jbotcan_database -f Dockerfile.database .
$CONTAINER_BIN build -t jbotcan/jbotcan_database --quiet=false -f Dockerfile.database . 2>&1 || {
  echo "Docker build failed."
  exit 1
}

db_port=14036

# We're exposing $db_port to the host here because you can't use
# --userns=keep-id with pods
# ( https://github.com/containers/libpod/issues/3993 ), and you
# can't share networks between containers with rootless containers (
# https://www.redhat.com/sysadmin/container-networking-podman ), so
# the only way for rootless containers running --userns=keep-id to
# talk to each other is across the host; we talk to "jukni" in
# LocalSettings.php for this reason.
$CONTAINER_BIN run --userns=keep-id --name jbotcan_database \
	-v /home/spjbotcan/jbotcan/database:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=aos8iexai0sieYei \
	-e MYSQL_DATABASE=jbotcan -e MYSQL_USER=jbotcan -e MYSQL_PASSWORD=ohphoratee2neeCh \
	-p $(facter networking.ip):$db_port:3306 \
	-i $hasterm jbotcan/jbotcan_database 2>&1

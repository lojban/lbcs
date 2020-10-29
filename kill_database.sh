#!/bin/bash

exec 2>&1
set -x

CONTAINER_BIN=${CONTAINER_BIN:-$(which podman)}
CONTAINER_BIN=${CONTAINER_BIN:-$(which docker)}

#**************
# Database
#**************
$CONTAINER_BIN stop --time=30 jbotcan_database 2>&1
$CONTAINER_BIN kill jbotcan_database 2>&1
$CONTAINER_BIN rm jbotcan_database 2>&1

exit 0

#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

chcon -R -t systemd_unit_file_t systemd/
if ! loginctl show-user "$(id -un)" | grep -q Linger=yes
then
    loginctl enable-linger "$(id -un)"
    if ! loginctl show-user "$(id -un)" | grep -q Linger=yes
    then
        echo -e "\n\n\nUSER LINGER DISABLED FOR THIS USER.  Could not fix this using 'loginctl show-user $(id -un)'.  Please investigate.\n\n\n" ;
    fi
fi

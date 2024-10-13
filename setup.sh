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

maindir="$(readlink -f "$(dirname "$0")")"
lbcsdir="$(dirname "$(readlink -f "$0")")"

echo -e "\nConfiguring user linger."
# Make sure the user has systemd "linger" turned on, so that their stuff starts
# when the system starts
if ! loginctl show-user "$(id -un)" | grep -q Linger=yes
then
    loginctl enable-linger "$(id -un)"
    if ! loginctl show-user "$(id -un)" | grep -q Linger=yes
    then
        echo -e "\n\n\nUSER LINGER DISABLED FOR THIS USER.  Could not fix this using 'loginctl show-user $(id -un)'.  Please investigate.\n\n\n" ;
    fi
fi

# First check to see if it's brand new
if [[ ! -d containers/ ]]
then
    maindir="$(pwd)"

    echo -ne "\n\nInitial setup detected.  MAKE SURE you're in the directory you want to create a bunch of new things in.  Current directory is $maindir\n\n"

    echo -ne "\n\nWhat do you want to name this bundle (AKA service/system/project/thingy) as a whole?  Examples are things like 'mymediawiki' or 'awesome_web_thingy', whereas containers will be named things like 'web' or 'db'.  "
    read -r bundle

    cat <<EOF >config
bundle=$bundle
web_port=9999
pod_args="-p \$web_port:\$web_port"
EOF

    echo -ne "\n\nWhat do you want to name the initial container? MUST NOT be the same as the bundle name. Something like 'web' is often a good choice.  "
    read -r name
    mkdir -p "containers/$name"
    cat <<EOF >"containers/$name/config"
description="FIXME: $bundle's $name container"
needs_network=true
# after_containers=db
name=$name
version=1
run_args='-v \$containerdir/src:/src'
run_program='sleep 999'
EOF
    cat <<EOF >"containers/$name/Dockerfile.erb"
<%= "\n"*30 %>
<%= "# YOU ARE IN THE WRONG PLACE" %>
<%= "# YOU ARE IN THE WRONG PLACE use the ERB file" %>
<%= "# YOU ARE IN THE WRONG PLACE" %>

FROM fedora:34
EOF

    echo -e "\n\nYou'll want to edit the config file, and the files in containers/$name\n\n"

    mkdir -p "$maindir/cron"

    echo -ne "\n\nWhat email address do you want cron output going to?  "
    read -r email

    cat <<EOF >"$maindir/cron/crontab.erb"
<%= "\n"*30 %>
<%= "# YOU ARE IN THE WRONG PLACE" %>
<%= "# CRONTAB MAINTANED BY LBCS" %>
<%= "# USE THE ERB FILE" %>
<%= "# YOU ARE IN THE WRONG PLACE" %>

LANG=en_US.UTF-8
MAILTO=$email
# Rebuild images every once in a while so we don't have surprises after a reboot of the host
$(shuf -i 0-59 -n 1) */5 * * * <%= maindir %>/rebuild_images.sh
EOF

    echo -e "\n\nIf you use SELinux, you should run initial_setup.sh as root, once.\n\n"
fi

ln -sf /opt/lbcs/README-Basic-Usage.txt .
ln -sf /opt/lbcs/build_image.sh .
ln -sf /opt/lbcs/rebuild_images.sh .
ln -sf /opt/lbcs/cron/cron-run-inside.sh cron/cron-run-inside.sh
ln -sf /opt/lbcs/destroy_container.sh .
ln -sf /opt/lbcs/initial_setup.sh .
ln -sf /opt/lbcs/run_container.sh .
ln -sf /opt/lbcs/run_addon.sh .
ln -sf /opt/lbcs/stop_addon.sh .
ln -sf /opt/lbcs/self_backup.sh .
ln -sf /opt/lbcs/self_restore_test.sh .
ln -sf /opt/lbcs/setup.sh .

# shellcheck disable=SC1091
. "$lbcsdir/config"
# shellcheck disable=SC1091
. "$maindir/config"
if [[ -f $maindir/secrets ]]
then
    # shellcheck disable=SC1091
    . "$maindir/secrets"
fi

if [[ ! ${bundle-} ]]
then
    echo "No bundle name (tag 'bundle') found in $maindir/config  ; please set.  (Used to be called 'service'.)"
    exit 1
fi

cd "$maindir"

echo -e "\nRegenerating systemd files."

mkdir -p ~/.config/systemd/user/default.target.wants

# shellcheck disable=SC2045
for container in $(ls -1 containers/)
do
    (
        # shellcheck disable=SC2034
        containerdir="containers/$container/"
        # shellcheck disable=SC1091,SC1090
        . "containers/$container/config"
        "$lbcsdir/lbcserb" "$maindir" "$lbcsdir" "$container" "$lbcsdir/systemd/template.service.erb" "$HOME/.config/systemd/user/$name.service" container
        rm -f "$HOME/.config/systemd/user/default.target.wants/$name.service"
        ln -s "$HOME/.config/systemd/user/$name.service" "$HOME/.config/systemd/user/default.target.wants/$name.service"
    )

    if [[ -d containers/$container/addons/ ]]
    then
        for addon in $(ls -1 "containers/$container/addons/")
        do
            (
                # shellcheck disable=SC2034
                addondir="containers/$container/addons/$addon/"
                # shellcheck disable=SC1091,SC1090
                . "containers/$container/addons/$addon/config"
                "$lbcsdir/lbcserb" "$maindir" "$lbcsdir" "$container" "$lbcsdir/systemd/template.service.erb" "$HOME/.config/systemd/user/$name.service" addon "$addon"
                rm -f "$HOME/.config/systemd/user/default.target.wants/$name.service"
                ln -s "$HOME/.config/systemd/user/$name.service" "$HOME/.config/systemd/user/default.target.wants/$name.service"
            )
        done
    fi
done

chcon -R -t systemd_unit_file_t ~/.config/systemd/

systemctl --user daemon-reload

# shellcheck disable=SC2045
for container in $(ls -1 containers/)
do
    # shellcheck disable=SC2034
    containerdir="containers/$container/"
    # shellcheck disable=SC1091,SC1090
    . "containers/$container/config"
    if [[ ! ${name-} ]]
    then
        echo "Can't find name for container $container in containers/$container/config; bailing setup."
        exit 1
    fi
    systemctl --user enable "$name"
    systemctl --user start "$name"
done

echo -e "\nSetting up cron."

for file in "$maindir"/cron/*.erb
do
    echo -e "\nERBing cron files: $file\n"

    "$lbcsdir/lbcserb" "$maindir" "$lbcsdir" "$container" "$file" "${file%.erb}" container userid="$(id -u)" groupid="$(id -g)"
done

if crontab -l 2>&1 | grep -q 'CRONTAB MAINTANED BY LBCS' || [[ $(crontab -l 2>&1 | grep -cv 'no crontab for') -eq 0 ]]
then
    if diff -q <(crontab -l 2>&1) "$maindir/cron/crontab" >/dev/null 2>&1
    then
        echo -e "\n\nNo crontab changes.\n\n"
    else
        echo -e "\n\nFound crontab changes:\n\n"
        diff <(crontab -l) "$maindir/cron/crontab" || true
        echo -e "\n\nUpdating crontab.\n\n"
        # We have to do it with the cat to avoid selinux fun
        # shellcheck disable=SC2002
        cat "$maindir/cron/crontab" | crontab -
    fi
else
    echo -e '\n\n*** ERROR: crontab does not appear to be LBCS generated; cowardly refusing to overwrite.\n\n'
fi

echo -e "\nChecking for template output ignores"
find "$maindir/" "${template_find-}" -type f -name '*.erb' -print >"/tmp/toi.$$"
# shellcheck disable=SC2002
if [[ $(cat "/tmp/toi.$$" | wc -l) -eq 0 ]]
then
    echo "No template files, no problem."
else
    if [[ ! -f $maindir/.gitignore ]]
    then
        echo -e '\n\nWARNING: You have template files but no .gitignore file; it is important that your template output files be in .gitignore, both to prevent accidental checkins of irrelevant crap and because they might have expanded secrets in them.\n\n'
    else
        comm -13 <(sort .gitignore) <(sed -e "s;^$maindir/;;" -e 's/\.erb$//' "/tmp/toi.$$" | sort | uniq) >"/tmp/toi-comm.$$"
        # shellcheck disable=SC2002
        if [[ $(cat /tmp/toi-comm.$$ | wc -l) -ne 0 ]]
        then
            echo -e '\n\nWARNING: The following files appear to be .erb/template generated and should probably be added to .gitignore. It is important that your template output files be in .gitignore, both to prevent accidental checkins of irrelevant crap and because they might have expanded secrets in them.\n'
            cat "/tmp/toi-comm.$$"
            echo -e '\n\n'
        fi
    fi
fi
rm -f "/tmp/toi.$$" "/tmp/toi-comm.$$"

echo

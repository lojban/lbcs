#!/bin/bash

shopt -s nullglob

maindir="$(readlink -f "$(dirname "$0")")"
lbcsdir="$(dirname "$(readlink -f "$0")")"

echo -e "\nConfiguring user linger."
# Make sure the user has systemd "linger" turned on, so that their stuff starts
# when the system starts
if ! loginctl show-user $(id -un) | grep -q Linger=yes
then
    loginctl enable-linger $(id -un)
    if ! loginctl show-user $(id -un) | grep -q Linger=yes
    then
        echo -e "\n\n\nUSER LINGER DISABLED FOR THIS USER.  Could not fix this using 'loginctl show-user $(id -un)'.  Please investigate.\n\n\n" ;
    fi
fi

# First check to see if it's brand new
if [[ ! -d containers/ ]]
then
    maindir=$(pwd)

    echo -ne "\n\nInitial setup detected.  MAKE SURE you're in the directory you want to create a bunch of new things in.  Current directory is $maindir\n\n"

    echo -ne "\n\nWhat do you want to name this service/system/thingy as a whole? (Actual systemd service names will be the same as the container names, by default.)  "
    read servicename

    cat <<EOF >config
service=$servicename
pod_args='-p 9999:9999'
EOF

    echo -ne "\n\nWhat do you want to name the initial container? MUST NOT be the same as the service name. Something like 'web' is often a good choice.  "
    read name
    mkdir -p containers/$name
    cat <<EOF >containers/$name/config
description="FIXME: $servicename's $name container"
needs_network=true
# after_containers=db
name=$name
version=1
run_args='-v $maindir/containers/$name/src:/src'
run_program='sleep 999'
EOF
    cat <<EOF >containers/$name/Dockerfile.erb
<%= "\n"*30 %>
<%= "# YOU ARE IN THE WRONG PLACE" %>
<%= "# YOU ARE IN THE WRONG PLACE use the ERB file" %>
<%= "# YOU ARE IN THE WRONG PLACE" %>

FROM fedora:31
EOF

    echo -e "\n\nYou'll want to edit the config file, and the files in containers/$name\n\n"

    mkdir -p $maindir/cron

    echo -ne "\n\nWhat email address do you want cron output going to?  "
    read email

    cat <<EOF >$maindir/cron/crontab.erb
<%= "\n"*30 %>
<%= "# YOU ARE IN THE WRONG PLACE" %>
<%= "# CRONTAB MAINTANED BY LBCS" %>
<%= "# USE THE ERB FILE" %>
<%= "# YOU ARE IN THE WRONG PLACE" %>
<%= "\n"*30 %>
LANG=en_US.UTF-8
MAILTO=$email
# Rebuild images every once in a while so we don't have surprises after a reboot of the host
$(shuf -i 0-59 -n 1) */5 * * * <%= maindir %>/rebuild_images.sh
EOF

    ln -sf /opt/lbcs/README-Basic-Usage.txt
    ln -sf /opt/lbcs/build_image.sh
    ln -sf /opt/lbcs/rebuild_images.sh
    ln -sf /opt/lbcs/cron/cron-run-inside.sh cron/cron-run-inside.sh
    ln -sf /opt/lbcs/destroy_container.sh
    ln -sf /opt/lbcs/initial_setup.sh
    ln -sf /opt/lbcs/run_container.sh
    ln -sf /opt/lbcs/setup.sh

    echo -e "\n\nIf you use SELinux, you should run initial_setup.sh as root, once.\n\n"
fi

cd "$maindir"

echo -e "\nRegenerating systemd files."

mkdir -p ~/.config/systemd/user/default.target.wants

for container in $(ls -1 containers/)
do
    (
        . containers/$container/config
        $lbcsdir/lbcserb $maindir $lbcsdir $container $lbcsdir/systemd/template.service.erb ~/.config/systemd/user/$name.service containers
        rm -f ~/.config/systemd/user/default.target.wants/$name.service
        ln -s ~/.config/systemd/user/$name.service ~/.config/systemd/user/default.target.wants/$name.service
    )
done

if [[ -d services/ ]]
then
    for service in $(ls -1 services/)
    do
        (
            . services/$service/config
            $lbcsdir/lbcserb $maindir $lbcsdir $service $lbcsdir/systemd/template.service.erb ~/.config/systemd/user/$name.service services
            rm -f ~/.config/systemd/user/default.target.wants/$name.service
            ln -s ~/.config/systemd/user/$name.service ~/.config/systemd/user/default.target.wants/$name.service
        )
    done
fi

chcon -R -t systemd_unit_file_t ~/.config/systemd/

systemctl --user daemon-reload

for container in $(ls -1 containers/)
do
    . containers/$container/config
    if [[ ! $name ]]
    then
        echo "Can't find name for container $container in containers/$container/config; bailing setup."
        exit 1
    fi
    systemctl --user enable $name
    systemctl --user start $name
done

echo -e "\nSetting up cron."

for file in $maindir/cron/*.erb
do
    echo -e "\nERBing cron files: $file\n"

    $lbcsdir/lbcserb $maindir $lbcsdir $container "$file" "$(echo "$file" | sed 's/\.erb$//')" containers userid=$(id -u) groupid=$(id -g)
done

if crontab -l 2>&1 | grep -q 'CRONTAB MAINTANED BY LBCS'
then
    if diff -q <(crontab -l) $maindir/cron/crontab >/dev/null 2>&1
    then
        echo -e "\n\nNo crontab changes.\n\n"
    else
        echo -e "\n\nFound crontab changes:\n\n"
        diff <(crontab -l) $maindir/cron/crontab
        echo -e "\n\nUpdating crontab.\n\n"
        cat $maindir/cron/crontab | crontab -
    fi
else
    echo -e '\n\n*** ERROR: crontab does not appear to be LBCS generated; cowardly refusing to overwrite.\n\n'
fi

echo -e "\nChecking for template output ignores"
find $maindir/ -type f -name '*.erb' >/tmp/toi.$$
if [[ $(cat /tmp/toi.$$ | wc -l) -eq 0 ]]
then
    echo "No template files, no problem."
else
    if [[ ! -f $maindir/.gitignore ]]
    then
        echo -e '\n\nWARNING: You have template files but no .gitignore file; it is important that your template output files be in .gitignore, both to prevent accidental checkins of irrelevant crap and because they might have expanded secrets in them.\n\n'
    else
        comm -13 <(sort .gitignore) <(cat /tmp/toi.$$ | sed -e "s;^$maindir/;;" -e 's/\.erb$//' | sort | uniq) >/tmp/toi-comm.$$
        if [[ $(cat /tmp/toi-comm.$$ | wc -l) -ne 0 ]]
        then
            echo -e '\n\nWARNING: The following files appear to be .erb/template generated and should probably be added to .gitignore. It is important that your template output files be in .gitignore, both to prevent accidental checkins of irrelevant crap and because they might have expanded secrets in them.\n'
            cat /tmp/toi-comm.$$
            echo -e '\n\n'
        fi
    fi
fi
rm -f /tmp/toi.$$ /tmp/toi-comm.$$

echo

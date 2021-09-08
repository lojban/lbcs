Terms
=====

The entire setup for your project/system/service/whatever is called
a "bundle"; the directory that has symlink to this file is your
bundle.  Bundles have one or more containers, and containers have
zero or more addons.  Containers and addons both run as systemd user
services.

Run Setup
=========

Every time you maake any non-trivial changes to the templates or the
container setup or anything, run ./setup.sh

Managing Normally
=================

( If you want to know how this stuff actually *works*, read
/opt/lbcs/README-Installation.txt )

This setup is managed by systemd over rootless podman, but the podman
part shouldn't normally be relevant, so here's some command examples
to perform basic operations:

# List all the things you could be running and their status; you can
# ignore things like "dbus-broker.service" and
# "grub-boot-success.service"
$ systemctl --user list-units --no-page -t service -a

# Show detailed status of what's running:
$ systemctl --user status

# Start a service; typically, if you start the web service, the DB
# service will also be started:
$ systemctl --user start jvs-web

# Restart a service
$ systemctl --user restart jvs-web

# Stop a service
$ systemctl --user stop jvs-web

# Show recent service logs
$ systemctl --user status jvs-web

# Show more logs:
$ systemctl --user status -n 100 jvs-web

# Logs another way:
$ journalctl --user -t jvs-web
$ journalctl --user -n 100

# Watch live logs:
$ journalctl -f -n 100 --user

Reminder:

Every time you maake any non-trivial changes to the templates or the
container setup or anything, run ./setup.sh

Managing Manually
=================

Each of the directories under containers/ is one of the containers
you can run.  You can pass those directory names as arguments to
various scripts, such as:

$ ./run_container.sh web

The following scripts take such arguments:

- run_container.sh starts a container
- destroy_container.sh destroys a container
- build_image.sh rebuilds the container image; normally only useful
  if you've changed the Dockerfile.erb file

NB: destroy_container.sh DESTROYS ALL LIVE STATE.  This is normally
fine, but if you need logs or something, do just the "kill"s and not
the "rm"s from that script, although note most of the logs are in
journalctl --user anyway.

The Containers
--------------

All aspects of the bundle run inside containers; you can see them
with "podman ps -a".  If you're like "what the hell is podman?",
just pretend it's docker and you should be fine.  If you're like
"what the hell is docker?", you shouldn't be trying to administer
this.

Problems
--------

If things are behaving strangly you can try

$ ./setup.sh

If you want to investigate what's happening inside a container:

$ podman exec -it [systemd container name, i.e. jvs-db] /bin/bash

To do stuff as root in the container:

$ podman exec -u root -it jvs-db /bin/bash 

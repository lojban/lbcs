# Must be run as root

# Should only be run once, ever.

maindir="$(readlink -f "$(dirname "$0")")"
lbcsdir="$(dirname "$(readlink -f "$0")")"

# May or may not be necessary in your setup.
#
# chcon -u staff_u -R $maindir

semanage fcontext -a -t container_file_t "$maindir/containers(/.*)?"
restorecon -Rv $maindir

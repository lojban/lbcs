#!/bin/bash
#
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

maindir="$(readlink -f "$(dirname "$0")")"
lbcsdir="$(dirname "$(readlink -f "$0")")"

if [[ ! ${1-} ]]
then
    echo "Need container name as single argument."
    exit 1
fi

container="$1"
containerdir="$maindir/containers/$container"

if [[ ! -d $containerdir ]]
then
    echo "Can't find container dir $containerdir"
    exit 1
fi

# Make shellcheck happy
name=''
run_program=''
pod_slirp4netns_extras=''

# shellcheck disable=SC1091
. "$lbcsdir/config"
# shellcheck disable=SC1091
. "$maindir/config"
if [[ -f $maindir/secrets ]]
then
    # shellcheck disable=SC1091
    . "$maindir/secrets"
fi

# shellcheck disable=SC1091
. "$containerdir/config"

if [[ -f $containerdir/secrets ]]
then
    # shellcheck disable=SC1091
    . "$containerdir/secrets"
fi

if [[ ! ${version-} ]]
then
    echo "No version (tag 'version') found in $containerdir/config ; please set. You can increment the version to force a rebuild of the docker container."
    exit 1
fi

if [[ ! ${bundle-} ]]
then
    echo "No bundle name (tag 'bundle') found in $maindir/config  ; please set.  (Used to be called 'service'.)"
    exit 1
fi

if [[ ! ${pod_args-} ]]
then
    echo "No pod arguments (tag 'pod_args') found in $maindir/config ; I am skeptical that your pod does not need even a '-p 1234' argument."
    exit 1
fi

if [[ ! ${run_args-} ]]
then
    echo "No container run arguments (tag 'run_args') found in $containerdir/config ; I am skeptical that your pod does not need even a '-v datadir:/data' argument."
    exit 1
fi

if [[ $bundle = "$name" ]]
then
    echo "The bundle name ($bundle) and the container name ($name) can't be the same; modify one of the config files to fix please."
    exit 1
fi

"$maindir/destroy_container.sh" "$container"

"$maindir/build_image.sh" "$container"

hasterm=''
if tty -s
then
    hasterm='-t'
fi

# If there's no containers running in this bundle, take the
# opportunity to rebuild the pod, in case anything has changed
#
# If there's only one container in the pod, that's the
# infrastructure container (or it's broken)
if [[ $($CONTAINER_BIN pod inspect "$bundle" 2>/dev/null | jq -r '.Containers | .[].State' 2>/dev/null | grep -c '^running$' 2>/dev/null) -le 1 ]]
then
    echo -e "\nPod $bundle appears to be empty; re-creating to pick up any config changes."
    $CONTAINER_BIN pod rm "$bundle" || true
fi

# Create a pod so that only the other containers in the pod (i.e. the web
# server) can see private things (i.e. the database)
if $CONTAINER_BIN pod exists "$bundle"
then
    echo -e "\nPod $bundle already exists\n"
else
    echo -e "\nCreating pod $bundle\n"

    userns="--userns=keep-id"
    if [[ ${no_userns-} ]]
    then
      userns=""
    fi

    # The port_handler=slirp4netns part here is to preserve source
    # IP info, at a slight cost in performance.
    #
    # The mtu=30000 part here is due to https://github.com/rootless-containers/slirp4netns/issues/284
    #
    # shellcheck disable=SC2086
    $CONTAINER_BIN pod create --share=net --network slirp4netns:mtu=30000,port_handler=slirp4netns$pod_slirp4netns_extras $userns -n "$bundle" $pod_args
fi

if [[ ${after_containers-} ]]
then
    for after_container in $after_containers
    do
        # shellcheck disable=SC2034
        for num in $(seq 1 10)
        do
            if [[ $($CONTAINER_BIN container inspect --format '{{.State.Status}}' "$after_container") == 'running' ]]
            then
                break
            fi
            echo -e "\nWaiting for required container $after_container to start.\n"
            sleep 30
        done

        if [[ $($CONTAINER_BIN container inspect --format '{{.State.Status}}' "$after_container") == 'running' ]]
        then
            echo -e "\nRequired container $after_container has started.\n"
        else
            echo -e "\nRequired container $after_container has not started; exiting.\n"
            exit 1
        fi
    done
fi

if [[ ${files_to_erb_on_run-} ]]
then
    echo -e "\nERBing runtime files\n"

    for file in $files_to_erb_on_run
    do
        echo "ERBing $maindir/$file.erb to $maindir/$file"
        "$lbcsdir/lbcserb" "$maindir" "$lbcsdir" "$container" "$maindir/$file.erb" "$maindir/$file" container
    done
fi

if [[ ${run_pre_script-} ]]
then
    echo -e "\nRunning pre-script for container $container\n"
    eval "$run_pre_script"
    echo -e "\nDone running pre-script for container $container\n"
fi

echo -e "\nRunning container $name for bundle $bundle\n"

# Need the eval to expand variables in $run_args itself; probably a better way
# to do this but meh
#
# --log-driver=none is because we're logging via systemd already; if
# we have podman do it as well we get double logging in journalctl
eval "$CONTAINER_BIN" run "--pod=$bundle" --log-driver=none --name "$name" \
    "$run_args" \
    -i "$hasterm" "$(id -un)/$bundle-$container:$version" "$run_program" 2>&1

if [[ ${run_post_script-} ]]
then
    echo -e "\nRunning post-script for container $container\n"
    eval "$run_post_script"
    echo -e "\nDone running post-script for container $container\n"
fi

echo "Running container $container complete"

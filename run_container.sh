#!/bin/bash

exec 2>&1
set -e

maindir="$(readlink -f "$(dirname "$0")")"
lbcsdir="$(dirname "$(readlink -f "$0")")"

container="$1"
containerdir="$maindir/containers/$container"

if [[ ! $container ]]
then
    echo "Need container name as single argument."
    exit 1
fi

if [[ ! -d $containerdir ]]
then
    echo "Can't find container dir $containerdir"
    exit 1
fi

. $lbcsdir/config
. $maindir/config
if [[ -f $maindir/secrets ]]
then
    . $maindir/secrets
fi
. $containerdir/config
if [[ -f $containerdir/secrets ]]
then
    . $containerdir/secrets
fi

if [[ ! $version ]]
then
    echo "No version (tag 'version') found in $containerdir/config ; please set. You can increment the version to force a rebuild of the docker container."
    exit 1
fi

if [[ ! $bundle ]]
then
    echo "No bundle name (tag 'bundle') found in $maindir/config  ; please set.  (Used to be called 'service'.)"
    exit 1
fi

if [[ ! $pod_args ]]
then
    echo "No pod arguments (tag 'pod_args') found in $maindir/config ; I am skeptical that your pod does not need even a '-p 1234' argument."
    exit 1
fi

if [[ ! $run_args ]]
then
    echo "No container run arguments (tag 'run_args') found in $containerdir/config ; I am skeptical that your pod does not need even a '-v datadir:/data' argument."
    exit 1
fi

if [[ $bundle = $name ]]
then
    echo "The bundle name ($bundle) and the container name ($name) can't be the same; modify one of the config files to fix please."
    exit 1
fi

$maindir/destroy_container.sh $container

$maindir/build_image.sh $container

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
if [[ $($CONTAINER_BIN pod inspect $bundle | jq -r '.Containers | .[].State' | grep '^running$' | wc -l) -le 1 ]]
then
    $CONTAINER_BIN pod rm $bundle || true
fi

# Create a pod so that only the other containers in the pod (i.e. the web
# server) can see private things (i.e. the database)
if $CONTAINER_BIN pod exists $bundle
then
    echo -e "\nPod $bundle already exists\n"
else
    $CONTAINER_BIN pod rm $bundle || true
    echo -e "\nCreating pod $bundle\n"
    $CONTAINER_BIN pod create --share=net -n $bundle $pod_args
fi

if [[ $after_containers ]]
then
    for after_container in $after_containers
    do
        for num in $(seq 1 10)
        do
            if [[ $($CONTAINER_BIN container inspect --format '{{.State.Status}}' $after_container) == 'running' ]]
            then
                break
            fi
            echo -e "\nWaiting for required container $after_container to start.\n"
            sleep 30
        done

        if [[ $($CONTAINER_BIN container inspect --format '{{.State.Status}}' $after_container) == 'running' ]]
        then
            echo -e "\nRequired container $after_container has started.\n"
        else
            echo -e "\nRequired container $after_container has not started; exiting.\n"
            exit 1
        fi
    done
fi

if [[ $files_to_erb_on_run ]]
then
    echo -e "\nERBing runtime files\n"

    for file in $files_to_erb_on_run
    do
        echo "ERBing $maindir/$file.erb to $maindir/$file"
        $lbcsdir/lbcserb $maindir $lbcsdir $container "$maindir/$file.erb" "$maindir/$file" containers
    done
fi

if [[ $run_pre_script ]]
then
    echo -e "\nRunning pre-script for container $container\n"
    bash -c "$(eval $run_pre_script)"
    echo -e "\nDone running pre-script for container $container\n"
fi

echo -e "\nRunning container $name for bundle $bundle\n"

userns="--userns=keep-id"
if [[ $no_userns ]]
then
  userns=""
fi

# Need the eval to expand variables in $run_args itself; probably a better way
# to do this but meh
eval $CONTAINER_BIN run --pod=$bundle $userns --name $name \
    $run_args \
    -i $hasterm $(id -un)/$bundle-$container:$version $run_program 2>&1

if [[ $run_post_script ]]
then
    echo -e "\nRunning post-script for container $container\n"
    bash -c "$run_post_script"
    echo -e "\nDone running post-script for container $container\n"
fi

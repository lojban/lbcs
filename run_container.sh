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

if [[ ! $service ]]
then
    echo "No service name (tag 'service') found in $maindir/config  ; please set."
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

$maindir/destroy_container.sh $container

$maindir/build_image.sh $container

hasterm=''
if tty -s
then
    hasterm='-t'
fi

# Create a pod so that only the other containers in the pod (i.e. the web
# server) can see private things (i.e. the database)
if $CONTAINER_BIN pod exists $service
then
    echo -e "\nPod $service already exists\n"
else
    echo -e "\nCreating pod $service\n"
    $CONTAINER_BIN pod create --share=net -n $service $pod_args
fi

if [[ $files_to_erb_on_run ]]
then
    echo -e "\nERBing runtime files\n"

    for file in $files_to_erb_on_run
    do
        echo "ERBing $maindir/$file.erb to $maindir/$file"
        $lbcsdir/lbcserb $maindir $lbcsdir $container $maindir/$file.erb > $maindir/$file
    done
fi

if [[ $run_pre_script ]]
then
    echo -e "\nRunning pre-script for service $service\n"
    bash -c "$(eval $run_pre_script)"
    echo -e "\nDone running pre-script for service $service\n"
fi

echo -e "\nRunning container $name for service $service\n"

# Need the eval to expand variables in $run_args itself; probably a better way
# to do this but meh
eval $CONTAINER_BIN run --pod=$service --userns=keep-id --name $name \
    $run_args \
    -i $hasterm $(id -un)/$service-$container:$version $run_program 2>&1

if [[ $run_post_script ]]
then
    echo -e "\nRunning post for service $service\n"
    bash -c "$run_post_script"
    echo -e "\nDone running post for service $service\n"
fi

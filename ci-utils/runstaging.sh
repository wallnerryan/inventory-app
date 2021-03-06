#!/usr/bin/env bash

set -e

# Script to run staging
# Needs to be run as SUDO

# -------------------- Params ---------------------------------------
# VOLUMESET        is a Flocker Hub Volumeset, which owns snapshots and variants
# HUBENDPOINT      is the Flocker Hub URL endpoint used by the CLI.
# SNAP             is a Flocker Hub Snapshot
# GITBRANCH        is the Github Branch name being built, it is provided by the Jenkins env.
# JENKINSBUILDURL  is the Jenkins Build ID URL, it is provided by the Jenkins env.
# JENKINSBUILDN    is the Jenkins Build Number
# --------------------- END -----------------------------------------

VOLUMESET=$1
HUBENDPOINT=$2
SNAP=$3
GITBRANCH=$4
JENKINSBUILDURL=$5
JENKINSBUILDN=$6
ENV="staging"

fli='docker run --rm --privileged -v /var/log/:/var/log/ -v /chq:/chq:shared -v /root:/root -v /lib/modules:/lib/modules clusterhq/fli'

check_for_failure() {
   if [ $? -eq 0 ]; then
      echo "OK"
   else
      echo "FAIL"
      exit 1
   fi
}

init_fli(){
   # Check if init has been run or if its a new slave.
   if [ ! -f /tmp/fliinitdone ]; then
      $fli setup --zpool chq || true
      touch /tmp/fliinitdone
      check_for_failure
      # vhut token is set as a secret inside the jenkins master
      $fli config -t /root/fh.token
      check_for_failure
      $fli config -u $HUBENDPOINT
      check_for_failure
   fi
}

use_snapshot() {
   echo "Use a specific snapshot"
   # Run `use_snap.sh` which pulls and creates volume from snapshot.
   # this script with modify in place the docker-compose.yml file
   # and add the /chq/<UUID> volume.
   ${GITBRANCH}-inventory-app/ci-utils/use_snap.sh ${VOLUMESET} ${SNAP} ${ENV} ${GITBRANCH}
}

start_app() {
   echo "Start with snapshot"
   # Start the application with the volume-from-snapshot.
   # Output so we can debug whether snapshot was placed
   # and start the compose app.
   cat ${GITBRANCH}-inventory-app/docker-compose.yml
   /usr/local/bin/docker-compose -f ${GITBRANCH}-inventory-app/docker-compose.yml up -d --build --remove-orphans
   # Show the containers in the log so we know what port to access.
   # we could use more accurate filtering, see https://docs.docker.com/engine/reference/commandline/ps/
   docker ps --last 2
   check_for_failure
}

# Used in teardown() and publish_staging_env()
L_NO_DASH_GITBRANCH=$(echo ${GITBRANCH//-} | tr '[:upper:]' '[:lower:]')

teardown() {
   echo "Teardown app if running"
   # Tear down the application and database again.
   /usr/local/bin/docker-compose -f ${GITBRANCH}-inventory-app/docker-compose.yml stop
   /usr/local/bin/docker-compose -f ${GITBRANCH}-inventory-app/docker-compose.yml rm -f
   docker volume rm ${L_NO_DASH_GITBRANCH}inventoryapp_rethink-data || true
}

publish_staging_env() {
   host=$(curl http://169.254.169.254/latest/meta-data/public-hostname)
   frontend_port=$(cut -d ":" -f 2 <<< $(sudo docker port ${L_NO_DASH_GITBRANCH}inventoryapp_frontend_1))
   check_for_failure
   rethinkdb_port=$(cut -d ":" -f 2 <<< $(sudo docker port ${L_NO_DASH_GITBRANCH}inventoryapp_db_1 | grep 28015))
   check_for_failure
   rethinkdb_ui_port=$(cut -d ":" -f 2 <<< $(sudo docker port ${L_NO_DASH_GITBRANCH}inventoryapp_db_1 | grep 8080))
   check_for_failure
   echo "Your staging environment is available at ${host}:${frontend_port}"
   echo "Your staging database is available at ${host}:${rethinkdb_port}"
   echo "Your staging database UI is available at ${host}:${rethinkdb_ui_port}"
}


run_group() {
   echo "Bringing up staging for ${GITBRANCH}-inventory-app with snapshot: ${SNAP}"
   init_fli
   teardown
   use_snapshot
   start_app
   publish_staging_env
}

run_group


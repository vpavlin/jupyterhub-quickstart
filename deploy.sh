#!/usr/bin/bash

function log() {
  echo "==> $@"
}

function err() {
  echo "!!! $@"
  exit 1
}

DEPLOYER_TEMPLATE=jupyterhub-deployer
IMAGE_STREAM_NAME=jupyterhub
IMAGE_STREAM_NAME_NOTEBOOK=minimal-notebook
CM_KEY_NAME="jupyterhub_config.py"
CM_NAME="${APPLICATION_NAME}-cfg"

SA_PREFIX="system:serviceaccount:"

[ -z ${APPLICATION_NAME} ] && err "You need to provide APPLICATION_NAME env var" 
[ -z ${JUPYTERHUB_CONFIG} ] && err "You need to provide JUPYTERHUB_CONFIG env var"
[ -e ${JUPYTERHUB_CONFIG} ] || err "JUPYTERHUB_CONFIG has to contain path to a config file" 

log "Using `oc whoami -c`"
echo -n "Press any key to continue... " && read

OPENSHIFT_URL=$(oc whoami --show-server)
[ $? -ne 0 ] && err "Failed to get OPENSHIFT_URL"

log "Checking connectivity to server ${OPENSHIFT_URL}..."
oc get pods &> /dev/null
[ $? -ne 0 ] && echo "Cannot talk to server" && exit 1

log "Checking ImageStream ${IMAGE_STREAM_NAME_NOTEBOOK}"
oc get is ${IMAGE_STREAM_NAME_NOTEBOOK} --no-headers -o name &> /dev/null
if [ $? -ne 0 ]; then
  log "ImageStream ${IMAGE_STREAM_NAME_NOTEBOOK} does not exist, applying..."
  oc create -f https://raw.githubusercontent.com/jupyter-on-openshift/jupyter-notebooks/master/images.json
fi

log "Checking ImageStream ${IMAGE_STREAM_NAME}"
oc get is ${IMAGE_STREAM_NAME} --no-headers -o name &> /dev/null
if [ $? -ne 0 ]; then
  log "ImageStream ${IMAGE_STREAM_NAME} does not exist, applying..."
  oc apply -f images.json
fi

log "Checking Template ${DEPLOYER_TEMPLATE}"
oc get template ${DEPLOYER_TEMPLATE} --no-headers -o name &> /dev/null
if [ $? -ne 0 ]; then
  log "Template ${DEPLOYER_TEMPLATE} does not exist, applying..."
  oc apply -f templates.yaml
fi

log "Deploying ${DEPLOYER_TEMPLATE} as ${APPLICATION_NAME}"
oc process ${DEPLOYER_TEMPLATE} -p APPLICATION_NAME=${APPLICATION_NAME} -p OPENSHIFT_URL=${OPENSHIFT_URL} | oc apply -f -

log "Updating config map ${CM_NAME} with content of ${JUPYTERHUB_CONFIG}"
oc get cm ${CM_NAME} -o yaml > ${CM_NAME}-cm.yaml.bckp
if [ $? -eq 0 ]; then
  oc delete cm ${CM_NAME}
  oc create cm ${CM_NAME} --from-file=${CM_KEY_NAME}=${JUPYTERHUB_CONFIG}
fi
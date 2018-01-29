#!/bin/bash
set -e

export ROOT_DIR=`pwd`
source $ROOT_DIR/concourse-vsphere/functions/copy_binaries.sh

export SCRIPT_DIR=$(dirname $0)
export NSX_GEN_OUTPUT_DIR=${ROOT_DIR}/nsx-gen-output
export NSX_GEN_OUTPUT=${NSX_GEN_OUTPUT_DIR}/nsx-gen-out.log
export NSX_GEN_UTIL=${NSX_GEN_OUTPUT_DIR}/nsx_parse_util.sh

if [ -e "${NSX_GEN_OUTPUT}" ]; then
  #echo "Saved nsx gen output:"
  #cat ${NSX_GEN_OUTPUT}
  source ${NSX_GEN_UTIL} ${NSX_GEN_OUTPUT}
else
  echo "Unable to retreive nsx gen output generated from previous nsx-gen-list task!!"
  exit 1
fi

export GOVC_INSECURE=1
export GOVC_URL=$GOVC_URL
export GOVC_USERNAME=$GOVC_USERNAME
export GOVC_PASSWORD=$GOVC_PASSWORD
export GOVC_DATACENTER=$GOVC_DATACENTER
export GOVC_DATASTORE=$GOVC_DATASTORE
export GOVC_NETWORK=$GOVC_NETWORK
export GOVC_RESOURCE_POOL=$GOVC_RESOURCE_POOL

function fn_get_pg {
  local search_string_net=$1
  local search_string="lsw-${NSX_EDGE_GEN_NAME}-${search_string_net}"
  vwire_pg=$(
  cat ${NSX_GEN_OUTPUT} | \
  grep ${search_string} | \
  grep -v "Effective" | awk '{print$5}' |  grep "virtualwire" | sort -u
  )
  echo $vwire_pg
}

function setPropertyMapping() {
  if [ -e out.json ]; then
    mv out.json in.json
  fi
  jq --arg key $1 \
     --arg value $2 \
     '(.PropertyMapping[] | select(.Key == $key)).Value = $value' \
                in.json >out.json
}

function setNetworkMapping() {
  if [ -e out.json ]; then
    mv out.json in.json
  fi
  jq --arg value $1 \
     '(.NetworkMapping[]).Network = $value' \
                in.json >out.json
}

function removeUnwantedNodes() {
  if [ -e out.json ]; then
    mv out.json in.json
  fi

  jq 'del(.Deployment)' in.json >out.json
}

function setVMName() {
  if [ -e out.json ]; then
    mv out.json in.json
  fi

  jq --arg value $1 \
     '(.).Name = $value' \
                in.json >out.json
}

function setDiskProvision() {
  if [ -e out.json ]; then
    mv out.json in.json
  fi

  jq --arg value $1 \
     '(.).DiskProvisioning = $value' \
                in.json >out.json
}

function setPowerOn() {
  if [ -e out.json ]; then
    mv out.json in.json
  fi

  if [ $1 ]; then
    jq '(.).PowerOn = true' \
                  in.json >out.json
  fi
}

function update() {
  rm -rf out.json

  setPropertyMapping ip0 $OM_IP
  setPropertyMapping netmask0 $OM_NETMASK
  setPropertyMapping gateway $OM_GATEWAY
  setPropertyMapping DNS $OM_DNS_SERVERS
  setPropertyMapping ntp_servers $OM_NTP_SERVERS
  setPropertyMapping admin_password $OPS_MGR_SSH_PWD
  setPropertyMapping custom_hostname $OPS_MGR_HOST

  setNetworkMapping $OM_VM_NETWORK
  setVMName $OM_VM_NAME
  setDiskProvision $OM_DISK_TYPE
  setPowerOn $OM_VM_POWER_STATE
  removeUnwantedNodes

  cat out.json
}

  echo "Detecting NSX Logical Switch Backing Port Groups..."
  # pushd nsx-edge-gen >/dev/null 2>&1
  # if [[ -e nsx_cloud_config.yml ]]; then rm -rf nsx_cloud_config.yml; fi
  # ./nsx-gen/bin/nsxgen -i $NSX_EDGE_GEN_NAME init

  if [[ $OM_VM_NETWORK = "nsxgen" ]]; then
     export OM_VM_NETWORK=$(fn_get_pg "Infra"); echo "Found $OM_VM_NETWORK"
  fi
  # popd >/dev/null 2>&1


FILE_PATH=`find ./pivnet-opsman-product/ -name *.ova`

echo $FILE_PATH

govc import.spec $FILE_PATH | python -m json.tool > om-import.json

mv om-import.json in.json

update

govc import.ova -options=out.json $FILE_PATH

rm *.json

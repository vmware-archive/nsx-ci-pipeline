#!/bin/bash

gunzip ./govc/govc_linux_amd64.gz
chmod +x ./govc/govc_linux_amd64
export PATH=$PATH:./govc

export GOVC_INSECURE=1
export GOVC_URL=$GOVC_URL
export GOVC_USERNAME=$GOVC_USERNAME
export GOVC_PASSWORD=$GOVC_PASSWORD

# Delete Active OpsMan
resource_pool_path=$(govc_linux_amd64 find . -name ${GOVC_RESOURCE_POOL} | grep -i resource )
possible_opsmans=$(govc_linux_amd64 find $resource_pool_path -type m -guest.ipAddress ${OPS_MGR_HOST} -runtime.powerState poweredOn)

# REMOVE ME - temporarily to clean up ops mgr
if [ "$possible_opsmans" == "" ]; then
  possible_opsmans=$(govc_linux_amd64 find $resource_pool_path -type m -name ${OPS_NAME} )
fi

for opsman in ${possible_opsmans}; do
  network="$(govc_linux_amd64 vm.info -r=true -json ${opsman} | jq -r '.VirtualMachines[0].Guest.Net[0].Network')"
  if [[ ${network} == ${GOVC_NETWORK} || ${network} == "" ]]; then
    echo "Powering off and removing ${opsman}..."
    set +e
    govc_linux_amd64 vm.power -vm.ipath=${opsman} -off
    set -e
    govc_linux_amd64 vm.destroy -vm.ipath=${opsman}
  fi
done

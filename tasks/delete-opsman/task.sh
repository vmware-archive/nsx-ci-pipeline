#!/bin/bash

gunzip ./govc/govc_linux_amd64.gz
chmod +x ./govc/govc_linux_amd64

export GOVC_IPATH="/Datacenter/vm/$OM_VM_NAME"
export GOVC_INSECURE=1
export GOVC_URL=$GOVC_URL
export GOVC_USERNAME=$GOVC_USERNAME
export GOVC_PASSWORD=$GOVC_PASSWORD

./govc/govc_linux_amd64 vm.destroy -vm.ipath=$GOVC_IPATH

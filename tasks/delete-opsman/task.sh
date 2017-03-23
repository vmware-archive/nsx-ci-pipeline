#!/bin/bash

gunzip ./govc/govc_linux_amd64.gz
chmod +x ./govc/govc_linux_amd64

export GOVC_IPATH="/Datacenter/vm/$OM_VM_NAME"

./govc/govc_linux_amd64 vm.destroy -vm.ipath=$GOVC_IPATH

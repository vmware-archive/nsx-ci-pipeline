#!/bin/bash
chmod +x om-cli/om-linux

export ROOT_DIR=`pwd`
export PATH=$PATH:$ROOT_DIR/om-cli
source $ROOT_DIR/concourse-vsphere/functions/check_versions.sh


om-linux \
	-t https://$OPS_MGR_HOST \
	-k -u $OPS_MGR_USR \
	-p $OPS_MGR_PWD \
	delete-installation \
|| om-linux \
	-t https://$OPS_MGR_HOST \
	-k -u $OPS_MGR_USR \
	-p $OPS_MGR_PWD \
	delete-installation

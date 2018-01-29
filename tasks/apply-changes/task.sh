#!/bin/bash -e


export ROOT_DIR=`pwd`
source $ROOT_DIR/concourse-vsphere/functions/copy_binaries.sh


om \
	-t https://$OPS_MGR_HOST \
	-k -u $OPS_MGR_USR \
	-p $OPS_MGR_PWD \
	curl -p "/api/v0/installations" \
	-x POST \
	-d '{ "ignore_warnings": "true" }'

om \
	-t https://$OPS_MGR_HOST \
	-k -u $OPS_MGR_USR \
	-p $OPS_MGR_PWD \
	apply-changes

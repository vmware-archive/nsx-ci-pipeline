#!/bin/bash


export ROOT_DIR=`pwd`
source $ROOT_DIR/concourse-vsphere/functions/copy_binaries.sh

METRICS_ERRANDS=$(cat <<-EOF
{"errands": [
  {"name": "integration-tests","post_deploy": false}
]}
EOF
)

METRICS_GUID=`om \
			-t https://$OPS_MGR_HOST \
			-k -u $OPS_MGR_USR \
			-p $OPS_MGR_PWD \
			curl -p "/api/v0/deployed/products" \
			-x GET \
			| jq '.[] | select(.type | contains("p-metrics")) | .installation_name' | tr -d '"'`

om \
	-t https://$OPS_MGR_HOST \
	-k -u $OPS_MGR_USR \
	-p $OPS_MGR_PWD \
	curl -p "/api/v0/staged/products/$METRICS_GUID/errands" \
	-x PUT \
	-d "$METRICS_ERRANDS"

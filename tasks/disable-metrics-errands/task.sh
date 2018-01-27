#!/bin/bash

chmod +x om-cli/om-linux

export ROOT_DIR=`pwd`
export PATH=$PATH:$ROOT_DIR/om-cli
source $ROOT_DIR/concourse-vsphere/functions/check_versions.sh


METRICS_ERRANDS=$(cat <<-EOF
{"errands": [
  {"name": "integration-tests","post_deploy": false}
]}
EOF
)

METRICS_GUID=`om-linux \
			-t https://$OPS_MGR_HOST \
			-k -u $OPS_MGR_USR \
			-p $OPS_MGR_PWD \
			curl -p "/api/v0/deployed/products" \
			-x GET \
			| jq '.[] | select(.type | contains("p-metrics")) | .installation_name' | tr -d '"'`

om-linux \
	-t https://$OPS_MGR_HOST \
	-k -u $OPS_MGR_USR \
	-p $OPS_MGR_PWD \
	curl -p "/api/v0/staged/products/$METRICS_GUID/errands" \
	-x PUT \
	-d "$METRICS_ERRANDS"

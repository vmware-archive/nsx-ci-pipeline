#!/bin/bash

chmod +x om-cli/om-linux

export ROOT_DIR=`pwd`
export PATH=$PATH:$ROOT_DIR/om-cli
source $ROOT_DIR/concourse-vsphere/functions/check_versions.sh


ERT_ERRANDS=$(cat <<-EOF
{"errands": [
  {"name": "smoke_tests","post_deploy": true},
  {"name": "push-usage-service","post_deploy": true},
  {"name": "push-apps-manager","post_deploy": true},
  {"name": "deploy-notifications","post_deploy": true},
  {"name": "deploy-notifications-ui","post_deploy": true},
  {"name": "push-pivotal-account","post_deploy": true},
  {"name": "deploy-autoscaling","post_deploy": true},
  {"name": "register-broker","post_deploy": true},
  {"name": "nfsbrokerpush","post_deploy": true}
]}
EOF
)

CF_GUID=`om-linux \
	-t https://$OPS_MGR_HOST \
	-k -u $OPS_MGR_USR \
	-p $OPS_MGR_PWD \
	curl -p "/api/v0/deployed/products" \
	-x GET \
	| jq '.[] | select(.installation_name | contains("cf-")) | .guid' | tr -d '"'`

om-linux \
	-t https://$OPS_MGR_HOST \
	-k -u $OPS_MGR_USR \
	-p $OPS_MGR_PWD \
	curl -p "/api/v0/staged/products/$CF_GUID/errands" \
	-x PUT \
	-d "$ERT_ERRANDS"

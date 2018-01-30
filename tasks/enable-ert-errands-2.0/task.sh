#!/bin/bash

export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-ci-pipeline/functions/copy_binaries.sh

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

CF_GUID=`om \
	-t https://$OPS_MGR_HOST \
	-k -u $OPS_MGR_USR \
	-p $OPS_MGR_PWD \
	curl -p "/api/v0/deployed/products" \
	-x GET \
	| jq '.[] | select(.installation_name | contains("cf-")) | .guid' | tr -d '"'`

om \
	-t https://$OPS_MGR_HOST \
	-k -u $OPS_MGR_USR \
	-p $OPS_MGR_PWD \
	curl -p "/api/v0/staged/products/$CF_GUID/errands" \
	-x PUT \
	-d "$ERT_ERRANDS" 2>/dev/null

#!/bin/bash

export ROOT_DIR=`pwd`
source $ROOT_DIR/concourse-vsphere/functions/copy_binaries.sh
source $ROOT_DIR/concourse-vsphere/functions/check_versions.sh

check_bosh_version
check_product_version "p-metrics"

om \
    -t https://$OPS_MGR_HOST \
    -u $OPS_MGR_USR \
    -p $OPS_MGR_PWD  \
    -k stage-product \
    -p $PRODUCT_NAME \
    -v $PRODUCT_VERSION

check_staged_product_guid "p-metrics"

NETWORK=$(cat <<-EOF
{
  "singleton_availability_zone": {
    "name": "$AZ_1"
  },
  "other_availability_zones": [
    { "name": "$AZ_1" }
  ],
  "network": {
    "name": "$NETWORK_NAME"
  }
}
EOF
)

PROPERTIES=$(cat <<-EOF
{
  ".maximus.credentials": {
    "value": {
      "identity": "$JMX_ADMIN_USR",
      "password": "$JMX_ADMIN_PWD"
    }
  },
  ".maximus.security_logging": {
    "value": $JMX_SECURITY_LOGGING
  },
  ".maximus.use_ssl": {
    "value": $JMX_USE_SSL
  }
}
EOF
)

RESOURCES=$(cat <<-EOF
{
  "maximus": {
    "instance_type": {"id": "automatic"},
    "instances" : 1
  },
  "opentsdb-firehose-nozzle": {
    "instance_type": {"id": "automatic"},
    "instances" : 1
  }
}
EOF
)

om \
    -t https://$OPS_MGR_HOST \
    -u $OPS_MGR_USR \
    -p $OPS_MGR_PWD \
    -k configure-product \
    -n $PRODUCT_NAME \
    -p "$PROPERTIES" \
    -pn "$NETWORK" \
    -pr "$RESOURCES"

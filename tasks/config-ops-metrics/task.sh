#!/bin/bash

chmod +x om-cli/om-linux

export ROOT_DIR=`pwd`
export PATH=$PATH:$ROOT_DIR/om-cli
source $ROOT_DIR/concourse-vsphere/functions/check_versions.sh

BOSH_VERSION=$(check_bosh_version)
PRODUCT_VERSION=$(check_product_version "p-metrics")

om-linux \
    -t https://$OPS_MGR_HOST \
    -u $OPS_MGR_USR \
    -p $OPS_MGR_PWD  \
    -k stage-product \
    -p $PRODUCT_NAME \
    -v $PRODUCT_VERSION

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

om-linux \
    -t https://$OPS_MGR_HOST \
    -u $OPS_MGR_USR \
    -p $OPS_MGR_PWD \
    -k configure-product \
    -n $PRODUCT_NAME \
    -p "$PROPERTIES" \
    -pn "$NETWORK" \
    -pr "$RESOURCES"

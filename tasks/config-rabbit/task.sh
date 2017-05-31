#!/bin/bash

set -e

chmod +x om-cli/om-linux

export ROOT_DIR=`pwd`
export SCRIPT_DIR=$(dirname $0)
export NSX_GEN_OUTPUT_DIR=${ROOT_DIR}/nsx-gen-output
export NSX_GEN_OUTPUT=${NSX_GEN_OUTPUT_DIR}/nsx-gen-out.log
export NSX_GEN_UTIL=${NSX_GEN_OUTPUT_DIR}/nsx_parse_util.sh

if [ -e "${NSX_GEN_OUTPUT}" ]; then
  source ${NSX_GEN_UTIL} ${NSX_GEN_OUTPUT}
else
  echo "Unable to retreive nsx gen output generated from previous nsx-gen-list task!!"
  exit 1
fi

TILE_RELEASE=`./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k available-products | grep p-rabbitmq`

PRODUCT_NAME=`echo $TILE_RELEASE | cut -d"|" -f2 | tr -d " "`
PRODUCT_VERSION=`echo $TILE_RELEASE | cut -d"|" -f3 | tr -d " "`

./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k stage-product -p $PRODUCT_NAME -v $PRODUCT_VERSION

function fn_get_azs {
     local azs_csv=$1
     echo $azs_csv | awk -F "," -v braceopen='{' -v braceclose='}' -v name='"name":' -v quote='"' -v OFS='"},{"name":"' '$1=$1 {print braceopen name quote $0 quote braceclose}'
}

TILE_AVAILABILITY_ZONES=$(fn_get_azs $TILE_AZS_RABBIT)


NETWORK=$(cat <<-EOF
{
  "singleton_availability_zone": {
    "name": "$TILE_AZ_RABBIT_SINGLETON"
  },
  "other_availability_zones": [
    $TILE_AVAILABILITY_ZONES
  ],
  "network": {
    "name": "$NETWORK_NAME"
  }
}
EOF
)

# Use RABBITMQ_TILE_LBR_IP & RABBITMQ_TILE_STATIC_IPS from nsx-edge-list
# PROPERTIES=$(cat <<-EOF
# {
#   ".rabbitmq-haproxy.static_ips": {
#     "value": "$TILE_RABBIT_PROXY_IPS"
#   },
#   ".rabbitmq-server.server_admin_credentials": {
#     "value": {
#       "identity": "$TILE_RABBIT_ADMIN_USER",
#       "password": "$TILE_RABBIT_ADMIN_PASSWD"
#     }
#   },
#   ".rabbitmq-broker.dns_host": {
#     "value": "$TILE_RABBIT_PROXY_VIP"
#   },
#   ".properties.metrics_tls_disabled": {
#     "value": false
#   }
# }
# EOF
# )

PROPERTIES=$(cat <<-EOF
{
  ".rabbitmq-haproxy.static_ips": {
    "value": "$RABBITMQ_TILE_STATIC_IPS"
  },
  ".rabbitmq-server.server_admin_credentials": {
    "value": {
      "identity": "$TILE_RABBIT_ADMIN_USER",
      "password": "$TILE_RABBIT_ADMIN_PASSWD"
    }
  },
  ".rabbitmq-broker.dns_host": {
    "value": "$RABBITMQ_TILE_LBR_IP"
  },
  ".properties.metrics_tls_disabled": {
    "value": false
  }
}
EOF
)

RESOURCES=$(cat <<-EOF
{
  "rabbitmq-haproxy": {
    "instance_type": {"id": "automatic"},
    "instances" : $TILE_RABBIT_PROXY_INSTANCES
  },
  "rabbitmq-server": {
    "instance_type": {"id": "automatic"},
    "instances" : $TILE_RABBIT_SERVER_INSTANCES
  }
}
EOF
)

./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k configure-product -n $PRODUCT_NAME -p "$PROPERTIES" -pn "$NETWORK" -pr "$RESOURCES"

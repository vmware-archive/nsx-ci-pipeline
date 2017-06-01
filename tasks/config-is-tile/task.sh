#!/bin/bash -e

chmod +x om-cli/om-linux
CMD=./om-cli/om-linux

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

# Can only support one version of the default isolation segment tile
# Search for the tile using the specified product name if available
# or search using p-iso as default iso product name
if [[ -z "$PRODUCT_NAME" ]]; then
  TILE_RELEASE=`./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k available-products | grep p-iso`
else
  TILE_RELEASE=`./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k available-products | grep $PRODUCT_NAME`
fi

PRODUCT_NAME=`echo $TILE_RELEASE | cut -d"|" -f2 | tr -d " "`
PRODUCT_VERSION=`echo $TILE_RELEASE | cut -d"|" -f3 | tr -d " "`

./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k stage-product -p $PRODUCT_NAME -v $PRODUCT_VERSION

function fn_get_azs {
     local azs_csv=$1
     echo $azs_csv | awk -F "," -v braceopen='{' -v braceclose='}' -v name='"name":' -v quote='"' -v OFS='"},{"name":"' '$1=$1 {print braceopen name quote $0 quote braceclose}'
}

TILE_AVAILABILITY_ZONES=$(fn_get_azs $TILE_AZS_ISO)


NETWORK=$(cat <<-EOF
{
  "singleton_availability_zone": {
    "name": "$TILE_AZ_ISO_SINGLETON"
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

if [[ -z "$SSL_CERT" ]]; then
DOMAINS=$(cat <<-EOF
  {"domains": ["*.$SYSTEM_DOMAIN", "*.$APPS_DOMAIN", "*.login.$SYSTEM_DOMAIN", "*.uaa.$SYSTEM_DOMAIN"] }
EOF
)

  CERTIFICATES=`$CMD -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl -p "$OPS_MGR_GENERATE_SSL_ENDPOINT" -x POST -d "$DOMAINS"`

  export SSL_CERT=`echo $CERTIFICATES | jq '.certificate' | tr -d '"'`
  export SSL_PRIVATE_KEY=`echo $CERTIFICATES | jq '.key' | tr -d '"'`

  echo "Using self signed certificates generated using Ops Manager..."

fi

# Supporting atmost 3 isolation segments
case "$NETWORK_NAME" in
  *01) 
  ROUTER_STATIC_IPS=$ISOZONE_SWITCH_1_GOROUTER_STATIC_IPS
  TCP_ROUTER_STATIC_IPS=$ISOZONE_SWITCH_1_TCPROUTER_STATIC_IPS
  ;;
  *02)
  ROUTER_STATIC_IPS=$ISOZONE_SWITCH_2_GOROUTER_STATIC_IPS
  TCP_ROUTER_STATIC_IPS=$ISOZONE_SWITCH_2_TCPROUTER_STATIC_IPS
  ;;
  *03)
  ROUTER_STATIC_IPS=$ISOZONE_SWITCH_3_GOROUTER_STATIC_IPS
  TCP_ROUTER_STATIC_IPS=$ISOZONE_SWITCH_3_TCPROUTER_STATIC_IPS
  ;;
esac

PROPERTIES=$(cat <<-EOF
{
  ".isolated_router.static_ips": {
    "value": "$ROUTER_STATIC_IPS"
  },
  ".isolated_diego_cell.executor_disk_capacity": {
    "value": "$CELL_DISK_CAPACITY"
  },
  ".isolated_diego_cell.executor_memory_capacity": {
    "value": "$CELL_MEMORY_CAPACITY"
  },
  ".isolated_diego_cell.garden_network_pool": {
    "value": "$APPLICATION_NETWORK_CIDR"
  },
  ".isolated_diego_cell.garden_network_mtu": {
    "value": $APPLICATION_NETWORK_MTU
  },
  ".isolated_diego_cell.insecure_docker_registry_list": {
    "value": "$INSECURE_DOCKER_REGISTRY_LIST"
  },
  ".isolated_diego_cell.placement_tag": {
    "value": "$SEGMENT_NAME"
  }
}
EOF
)

RESOURCES=$(cat <<-EOF
{
  "isolated_router": {
    "instance_type": {"id": "automatic"},
    "instances" : $IS_ROUTER_INSTANCES
  },
  "isolated_diego_cell": {
    "instance_type": {"id": "automatic"},
    "instances" : $IS_DIEGO_CELL_INSTANCES
  }
}
EOF
)

$CMD -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k configure-product -n $PRODUCT_NAME -p "$PROPERTIES" -pn "$NETWORK" -pr "$RESOURCES"

if [[ "$SSL_TERMINATION_POINT" == "terminate_at_router" ]]; then
echo "Terminating SSL at the goRouters and using self signed/provided certs..."
SSL_PROPERTIES=$(cat <<-EOF
{
  ".properties.networking_point_of_entry": {
    "value": "$SSL_TERMINATION_POINT"
  },
  ".properties.networking_point_of_entry.terminate_at_router.ssl_rsa_certificate": {
    "value": {
      "cert_pem": "$SSL_CERT",
      "private_key_pem": "$SSL_PRIVATE_KEY"
    }
  },
  ".properties.networking_point_of_entry.terminate_at_router.ssl_ciphers": {
    "value": "$ROUTER_SSL_CIPHERS"
  }
}
EOF
)

elif [[ "$SSL_TERMINATION_POINT" == "terminate_at_router_ert_cert" ]]; then
echo "Terminating SSL at the goRouters and reusing self signed/provided certs from ERT tile..."
SSL_PROPERTIES=$(cat <<-EOF
{
  ".properties.networking_point_of_entry": {
    "value": "$SSL_TERMINATION_POINT"
  }
}
EOF
)

elif [[ "$SSL_TERMINATION_POINT" == "terminate_before_router" ]]; then
echo "Unencrypted traffic to goRouters as SSL terminated at load balancer..."
SSL_PROPERTIES=$(cat <<-EOF
{
  ".properties.networking_point_of_entry": {
    "value": "$SSL_TERMINATION_POINT"
  }
}
EOF
)

fi

$CMD -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k configure-product -n $PRODUCT_NAME -p "$SSL_PROPERTIES"


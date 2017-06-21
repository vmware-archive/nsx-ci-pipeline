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
  # Read back associate array of jobs to lbr details
  # created by hte NSX_GEN_UTIL script
  source /tmp/jobs_lbr_map.out
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


# Support NSX LBR Integration

ISO_GUID=$(./om-cli/om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
                     curl -p "/api/v0/staged/products" -x GET \
                     | jq '.[] | select(.installation_name | contains("p-isolation-segment-")) | .guid' | tr -d '"')

# $ISO_TILE_JOBS_REQUIRING_LBR comes filled by nsx-edge-gen list command
# Sample: ERT_TILE_JOBS_REQUIRING_LBR='mysql_proxy,tcp_router,router,diego_brain'
JOBS_REQUIRING_LBR=$ISO_TILE_JOBS_REQUIRING_LBR

# Change to pattern for grep
JOBS_REQUIRING_LBR_PATTERN=$(echo $JOBS_REQUIRING_LBR | sed -e 's/,/\\|/g')

# Get job guids for cf (from staged product)
for job_guid in $(./om-cli/om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
                              curl -p "/api/v0/staged/products/${ISO_GUID}/jobs" 2>/dev/null \
                              | jq '.[] | .[] | .guid' | tr -d '"')
do
  echo $job_guid | grep -e $JOBS_REQUIRING_LBR_PATTERN
  if [ "$?" == "0" ]; then
    echo "$job requires Loadbalancer..."
    for job_requiring_lbr in $(echo $JOBS_REQUIRING_LBR | sed -e 's/,/ /g')
    do
      echo $job_guid | grep -i $job_requiring_lbr
      # Got matching job...
      if [ "$?" == "0" ]; then
        # The associative array comes from sourcing the /tmp/jobs_lbr_map.out file
        # filled earlier by nsx-edge-gen list command
        # Sample associative array content:
        # ERT_TILE_JOBS_LBR_MAP=( ["mysql_proxy"]="$ERT_MYSQL_LBR_DETAILS" ["tcp_router"]="$ERT_TCPROUTER_LBR_DETAILS" 
        # .. ["diego_brain"]="$SSH_LBR_DETAILS"  ["router"]="$ERT_GOROUTER_LBR_DETAILS" )
        # SSH_LBR_DETAILS=[diego_brain]="esg-sabha6:VIP-diego-brain-tcp-21:diego-brain21-Pool:2222"
        LBR_DETAILS=${MYSQL_TILE_JOBS_LBR_MAP[$job_requiring_lbr]}

        # Atmost we support 3 iso segments...
        case "$NETWORK_NAME" in
          *01) 
          LBR_DETAILS=${ISO_TILE_1_JOBS_LBR_MAP[$job_requiring_lbr]}
          ;;
          *02)
          LBR_DETAILS=${ISO_TILE_2_JOBS_LBR_MAP[$job_requiring_lbr]}
          ;;
          *03)
          LBR_DETAILS=${ISO_TILE_3_JOBS_LBR_MAP[$job_requiring_lbr]}
          ;;
        esac


        for variable in $(echo $LBR_DETAILS)
        do
          edge_name=$(echo $variable | awk -F ':' '{print $1}')
          lbr_name=$(echo $variable | awk -F ':' '{print $2}')
          pool_name=$(echo $variable | awk -F ':' '{print $3}')
          port=$(echo $variable | awk -F ':' '{print $4}')
          echo "ESG: $edge_name, LBR: $lbr_name, Pool: $pool_name and Port: $port"
          NSX_LBR_PAYLOAD=$(echo { \"nsx_lbs\": { \"edge_name\": \"$edge_name\", \"pool_name\": \"$pool_name\", \"port\": \"$port\" }  })
          echo Job: $job_requiring_lbr with GUID: $job_guid and NSX_LBR_PAYLOAD : "$NSX_LBR_PAYLOAD"

          # Register job with NSX Pool in Ops Mgr (gets passed to Bosh)
          ./om-cli/om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
              curl -p "/api/v0/staged/products/${ISO_GUID}/jobs/${job_guid}/resource_config" \ 
                -X PUT \ 
              -d "${NSX_LBR_PAYLOAD}"

          # Similar call required for registering security groups
          # ./om-cli/om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
          #     curl -p "/api/v0/staged/products/${ISO_GUID}/jobs/${job_guid}/resource_config" \ 
          #       -X PUT \ 
          #     -d '{"nsx_security_groups": ["SECURITY-GROUP1", "SECURITY-GROUP2"]}' 

        done
        continue
      fi
    done
  fi
done

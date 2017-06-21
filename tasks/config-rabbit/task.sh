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
  # Read back associate array of jobs to lbr details
  # created by hte NSX_GEN_UTIL script
  source /tmp/jobs_lbr_map.out
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

# Support NSX LBR Integration

RABBITMQ_GUID=$(./om-cli/om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
                     curl -p "/api/v0/staged/products" -x GET \
                     | jq '.[] | select(.installation_name \
                     | contains("mysql-")) | .guid' | tr -d '"')

# $RABBITMQ_TILE_JOBS_REQUIRING_LBR comes filled by nsx-edge-gen list command
# Sample: ERT_TILE_JOBS_REQUIRING_LBR='mysql_proxy,tcp_router,router,diego_brain'
JOBS_REQUIRING_LBR=$RABBITMQ_TILE_JOBS_REQUIRING_LBR

# Change to pattern for grep
JOBS_REQUIRING_LBR_PATTERN=$(echo $JOBS_REQUIRING_LBR | sed -e 's/,/\\|/g')

# Get job guids for cf (from staged product)
for job_guid in $(./om-cli/om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
                              curl -p "/api/v0/staged/products/${RABBITMQ_GUID}/jobs" 2>/dev/null \
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
        LBR_DETAILS=${RABBITMQ_TILE_JOBS_LBR_MAP[$job_requiring_lbr]}

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
              curl -p "/api/v0/staged/products/${RABBITMQ_GUID}/jobs/${job_guid}/resource_config" \ 
                -X PUT \ 
              -d "${NSX_LBR_PAYLOAD}"

          # Similar call required for registering security groups
          # ./om-cli/om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
          #     curl -p "/api/v0/staged/products/${RABBITMQ_GUID}/jobs/${job_guid}/resource_config" \ 
          #       -X PUT \ 
          #     -d '{"nsx_security_groups": ["SECURITY-GROUP1", "SECURITY-GROUP2"]}' 

        done
        continue
      fi
    done
  fi
done
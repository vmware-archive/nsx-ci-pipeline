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
  IS_NSX_ENABLED=$(./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k \
               curl -p "/api/v0/deployed/director/manifest" 2>/dev/null | jq '.cloud_provider.properties.vcenter.nsx' || true )

else
  echo "Unable to retreive nsx gen output generated from previous nsx-gen-list task!!"
  exit 1
fi

# Check if Bosh Director is v1.11 or higher
export BOSH_PRODUCT_VERSION=$(./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k \
           curl -p "/api/v0/deployed/products" 2>/dev/null | jq '.[] | select(.installation_name=="p-bosh") | .product_version' | tr -d '"')
export BOSH_MAJOR_VERSION=$(echo $BOSH_PRODUCT_VERSION | awk -F '.' '{print $1}' )
export BOSH_MINOR_VERSION=$(echo $BOSH_PRODUCT_VERSION | awk -F '.' '{print $2}' )


export IS_ERRAND_WHEN_CHANGED_ENABLED=false
if [ "$BOSH_MAJOR_VERSION" -le 1 ]; then
  if [ "$BOSH_MINOR_VERSION" -ge 10 ]; then
    export IS_ERRAND_WHEN_CHANGED_ENABLED=true
  fi
else
  export IS_ERRAND_WHEN_CHANGED_ENABLED=true
fi

TILE_RELEASE=`./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k available-products | grep p-rabbitmq`

export PRODUCT_NAME=`echo $TILE_RELEASE | cut -d"|" -f2 | tr -d " "`
export PRODUCT_VERSION=`echo $TILE_RELEASE | cut -d"|" -f3 | tr -d " "`
export PRODUCT_MAJOR_VERSION=$(echo $PRODUCT_VERSION | awk -F '.' '{print $1}' )
export PRODUCT_MINOR_VERSION=$(echo $PRODUCT_VERSION | awk -F '.' '{print $2}' )

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

# Add the static ips to list above if nsx not enabled in Bosh director 
# If nsx enabled, a security group would be dynamically created with vms 
# and associated with the pool by Bosh
if [ "$IS_NSX_ENABLED" == "null" -o "$IS_NSX_ENABLED" == "" ]; then
  PROPERTIES=$(cat <<-EOF
{
  ".rabbitmq-haproxy.static_ips": {
    "value": "$RABBITMQ_TILE_STATIC_IPS"
  },
EOF
)
else
  PROPERTIES="{"
fi

PROPERTIES=$(cat <<-EOF
$PROPERTIES
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

PRODUCT_GUID=$(./om-cli/om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
                     curl -p "/api/v0/staged/products" -x GET \
                     | jq '.[] | select(.installation_name | contains("p-rabbitmq-")) | .guid' | tr -d '"')


# Set Errands to on Demand for 1.10
if [ "$IS_ERRAND_WHEN_CHANGED_ENABLED" == "true" ]; then
  echo "applying errand configuration"
  sleep 6
  RABBITMQ_ERRANDS=$(cat <<-EOF
{"errands":[
  {"name":"broker-registrar","post_deploy":"when-changed"}
  ]
}
EOF
)

  ./om-cli/om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
                              curl -p "/api/v0/staged/products/$PRODUCT_GUID/errands" \
                              -x PUT -d "$RABBITMQ_ERRANDS"
fi

# Proceed if NSX is enabled on Bosh Director
# Support NSX LBR Integration
# if nsx is not enabled, skip remaining steps
if [ "$IS_NSX_ENABLED" == "null" -o "$IS_NSX_ENABLED" == "" ]; then
  exit
fi



# $RABBITMQ_TILE_JOBS_REQUIRING_LBR comes filled by nsx-edge-gen list command
# Sample: ERT_TILE_JOBS_REQUIRING_LBR='mysql_proxy,tcp_router,router,diego_brain'
JOBS_REQUIRING_LBR=$RABBITMQ_TILE_JOBS_REQUIRING_LBR

# Change to pattern for grep
JOBS_REQUIRING_LBR_PATTERN=$(echo $JOBS_REQUIRING_LBR | sed -e 's/,/\\|/g')

# Get job guids for deployment (from staged product)
./om-cli/om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
                              curl -p "/api/v0/staged/products/${PRODUCT_GUID}/jobs" 2>/dev/null \
                              | jq '.[] | .[] ' > /tmp/jobs_list.log

for job_guid in $(cat /tmp/jobs_list.log | jq '.guid' | tr -d '"')
do
  job_name=$(cat /tmp/jobs_list.log | grep -B1 $job_guid | grep name | awk -F '"' '{print $4}')
  job_name_upper=$(echo ${job_name^^} | sed -e 's/-/_/')
  
  # Check for security group defined for the given job from Env
  # Expecting only one security group env variable per job (can have a comma separated list)
  SECURITY_GROUP=$(env | grep "TILE_RABBIT_${job_name_upper}_SECURITY_GROUP" | awk -F '=' '{print $2}')

  match=$(echo $job_name | grep -e $JOBS_REQUIRING_LBR_PATTERN  || true)
  if [ "$match" != "" -o  "$SECURITY_GROUP" != "" ]; then
    echo "$job requires Loadbalancer or security group..."

    # Use an auto-security group based on product guid by Bosh 
    # for grouping all vms with the same security group
    NEW_SECURITY_GROUP=\"${PRODUCT_GUID}\"
     # Check if there are multiple security groups
    # If so, wrap them with quotes
    for secgrp in $(echo $SECURITY_GROUP |sed -e 's/,/ /g' )
    do
      NEW_SECURITY_GROUP=$(echo $NEW_SECURITY_GROUP, \"$secgrp\",)
    done
    SECURITY_GROUP=$(echo $NEW_SECURITY_GROUP | sed -e 's/,$//')

    # The associative array comes from sourcing the /tmp/jobs_lbr_map.out file
    # filled earlier by nsx-edge-gen list command
    # Sample associative array content:
    # ERT_TILE_JOBS_LBR_MAP=( ["mysql_proxy"]="$ERT_MYSQL_LBR_DETAILS" ["tcp_router"]="$ERT_TCPROUTER_LBR_DETAILS" 
    # .. ["diego_brain"]="$SSH_LBR_DETAILS"  ["router"]="$ERT_GOROUTER_LBR_DETAILS" )
    # SSH_LBR_DETAILS=[diego_brain]="esg-sabha6:VIP-diego-brain-tcp-21:diego-brain21-Pool:2222"
    LBR_DETAILS=${RABBITMQ_TILE_JOBS_LBR_MAP[$job_name]}

    RESOURCE_CONFIG=$(./om-cli/om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
                      curl -p "/api/v0/staged/products/${PRODUCT_GUID}/jobs/${job_guid}/resource_config" \
                      2>/dev/null)
    #echo "Resource config : $RESOURCE_CONFIG"
    # Remove trailing brace to add additional elements
    # Remove also any empty nsx_security_groups
    # Sample RESOURCE_CONFIG with nsx_security_group comes middle with ','
    # { "instance_type": { "id": "automatic" },
    #   "instances": 1,
    #   "nsx_security_groups": null,
    #   "persistent_disk": { "size_mb": "1024" }
    # }
    # or nsx_security_group comes last without ','
    # { "instance_type": { "id": "automatic" },
    #   "instances": 1,
    #   "nsx_security_groups": null
    # }
    # Strip the ending brace and also "nsx_security_group": null

    # Strip last braces
    RESOURCE_CONFIG1=$(echo $RESOURCE_CONFIG | sed -e '$ s/}$//')
    # Strip any empty nsx_security_groups
    RESOURCE_CONFIG1=$(echo $RESOURCE_CONFIG1 | sed -e 's/"nsx_security_groups": null//')
    # Remove any empty parameters and strip any existing last commas
    RESOURCE_CONFIG=$(echo $RESOURCE_CONFIG1 | sed -e 's/, ,/,/g' | sed -e '$ s/,$//' )
    # Now add back a comma so we can add additional parameters
    RESOURCE_CONFIG=$(echo "$RESOURCE_CONFIG ,")
        
    NSX_LBR_PAYLOAD=" \"nsx_lbs\": ["

    index=1
    for variable in $(echo $LBR_DETAILS)
    do
      edge_name=$(echo $variable | awk -F ':' '{print $1}')
      lbr_name=$(echo $variable  | awk -F ':' '{print $2}')
      pool_name=$(echo $variable | awk -F ':' '{print $3}')
      port=$(echo $variable | awk -F ':' '{print $4}')
      monitor_port=$(echo $variable | awk -F ':' '{print $5}')
      echo "ESG: $edge_name, LBR: $lbr_name, Pool: $pool_name, Port: $port, Monitor port: $monitor_port"
      
      # Create a security group with Product Guid and job name for lbr security grp
      job_security_grp=${PRODUCT_GUID}-${job_name}

      #ENTRY="{ \"edge_name\": \"$edge_name\", \"pool_name\": \"$pool_name\", \"port\": \"$port\", \"security_group\": \"$job_security_grp\" }"
      ENTRY="{ \"edge_name\": \"$edge_name\", \"pool_name\": \"$pool_name\", \"port\": \"$port\", \"monitor_port\": \"$monitor_port\", \"security_group\": \"$job_security_grp\" }"
      #echo "Created lbr entry for job: $job_guid with value: $ENTRY"

      if [ "$index" == "1" ]; then          
        NSX_LBR_PAYLOAD=$(echo "$NSX_LBR_PAYLOAD $ENTRY ")
      else
        NSX_LBR_PAYLOAD=$(echo "$NSX_LBR_PAYLOAD, $ENTRY ")
      fi
      index=$(expr $index + 1)
    done

    NSX_LBR_PAYLOAD=$(echo "$NSX_LBR_PAYLOAD ] ")
    #echo "Job: $job_name with GUID: $job_guid and NSX_LBR_PAYLOAD : $NSX_LBR_PAYLOAD"

    UPDATED_RESOURCE_CONFIG=$(echo "$RESOURCE_CONFIG \"nsx_security_groups\": [ $SECURITY_GROUP ], $NSX_LBR_PAYLOAD }")
    echo "Job: $job_name with GUID: $job_guid and RESOURCE_CONFIG : $UPDATED_RESOURCE_CONFIG"

    # Register job with NSX Pool in Ops Mgr (gets passed to Bosh)
    ./om-cli/om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD  \
            curl -p "/api/v0/staged/products/${PRODUCT_GUID}/jobs/${job_guid}/resource_config"  \
            -x PUT  -d "${UPDATED_RESOURCE_CONFIG}"

  fi
done

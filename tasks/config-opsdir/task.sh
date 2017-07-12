#!/bin/bash
set -e

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

openssl s_client  -servername $NSX_MANAGER_ADDRESS \
                  -connect ${NSX_MANAGER_ADDRESS}:443 \
                  </dev/null 2>/dev/null \
                  | openssl x509 -text \
                  >  /tmp/complete_nsx_manager.log

# Get the host name instead of ip
if [ "$NSX_MANAGER_FQDN" == "" ]; then
  echo "Fully qualified domain name for NSX Manager not provided, looking up from the NSX Manager cert!!"
  
  NSX_MANAGER_HOST_ADDRESS=`cat /tmp/complete_nsx_manager.log \
                          | grep Subject | grep "CN=" \
                          | awk '{print $NF}' \
                          | sed -e 's/CN=//g' `
else
  NSX_MANAGER_HOST_ADDRESS=$NSX_MANAGER_FQDN
fi

echo "Fully qualified domain name for NSX Manager: $NSX_MANAGER_HOST_ADDRESS"
  
NO_OF_FIELDS=$(echo "$NSX_MANAGER_HOST_ADDRESS" | awk -F '.' '{print NF}')
if [ $NO_OF_FIELDS -lt 3 ]; then
  echo "Fully qualified domain name for NSX Manager not provided nor available from the given NSX Manager cert!!"
  exit 1
fi

cat /tmp/complete_nsx_manager.log \
                  |  awk '/BEGIN /,/END / {print }' \
                  >  /tmp/nsx_manager.cert

# Strip newlines and replace them with \r\n
cat /tmp/nsx_manager.cert | tr '\n' '#'| sed -e 's/#/\\r\\n/g'   > /tmp/nsx_manager.edited_cert

#CSV parsing Function for mutiple AZs

function fn_get_azs {
     local azs_csv=$1
     echo $azs_csv | awk -F "," -v quote='"' -v OFS='", "' '$1=$1 {print quote $0 quote}'
}

function fn_get_pg {
  local search_string_net=$1
  local search_string="lswitch-${NSX_EDGE_GEN_NAME}-${search_string_net}"
  vwire_pg=$(
  cat ${NSX_GEN_OUTPUT} | \
  grep ${search_string} | \
  grep -v "Effective" | awk '{print$5}' |  grep "virtualwire" | sort -u
  )
  echo $vwire_pg
}

function fn_get_component_static_ips {
  local search_switch=$1
  local search_component=$2
  component_static_ips=$(
  cat ${NSX_GEN_OUTPUT} | \
   grep  "static ips" |
   grep ${search_switch} | \
   grep ${search_component} | \
   awk -F '|' '{print$5}' 
  )
  echo $component_static_ips
}

# Check for Errors with obtaining the networks
if [ "$INFRA_VCENTER_NETWORK" == "" \
  -o "$DEPLOYMENT_VCENTER_NETWORK" == "" \
  -o "$SERVICES_VCENTER_NETWORK" == "" \
  -o "$DYNAMIC_SERVICES_VCENTER_NETWORK" == "" ]; then 
  echo "Some networks could not be located from NSX!!"
  echo "      INFRASTRUCTURE: $INFRA_VCENTER_NETWORK"
  echo "      ERT DEPLOYMENT: $DEPLOYMENT_VCENTER_NETWORK"
  echo "      SERVICES: $SERVICES_VCENTER_NETWORK"
  echo "      DYNAMIC SERVICES: $DYNAMIC_SERVICES_VCENTER_NETWORK"
  exit 1
fi

# IAAS_CONFIGURATION=$(cat <<-EOF
# {
#   "vcenter_host": "$VCENTER_HOST",
#   "vcenter_username": "$VCENTER_USR",
#   "vcenter_password": "$VCENTER_PWD",
#   "datacenter": "$VCENTER_DATA_CENTER",
#   "disk_type": "$VCENTER_DISK_TYPE",
#   "ephemeral_datastores_string": "$STORAGE_NAMES",
#   "persistent_datastores_string": "$STORAGE_NAMES",
#   "bosh_vm_folder": "pcf_vms",
#   "bosh_template_folder": "pcf_templates",
#   "bosh_disk_path": "pcf_disk",
#   "ssl_verification_enabled": false,
#   "nsx_networking_enabled": true,
#   "nsx_address": "${NSX_MANAGER_ADDRESS}",
#   "nsx_username": "${NSX_MANAGER_ADMIN_USER}",
#   "nsx_ca_certificate": "${NSX_MANAGER_CA_CERT}"
# }
# EOF
# )

# Fill default iaas conf
cat > /tmp/iaas_conf.txt <<-EOF
{
  "vcenter_host": "$VCENTER_HOST",
  "vcenter_username": "$VCENTER_USR",
  "vcenter_password": "$VCENTER_PWD",
  "datacenter": "$VCENTER_DATA_CENTER",
  "disk_type": "$VCENTER_DISK_TYPE",
  "ephemeral_datastores_string": "$STORAGE_NAMES",
  "persistent_datastores_string": "$STORAGE_NAMES",
  "bosh_vm_folder": "pcf_vms",
  "bosh_template_folder": "pcf_templates",
  "bosh_disk_path": "pcf_disk",
  "ssl_verification_enabled": false
}
EOF

# Check if Bosh Director is v1.11 or higher
export BOSH_PRODUCT_VERSION=$(./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k \
           curl -p "/api/v0/staged/products" 2>/dev/null | jq '.[].product_version' | tr -d '"')
export BOSH_MAJOR_VERSION=$(echo $BOSH_PRODUCT_VERSION | awk -F '.' '{print $1}' )
export BOSH_MINOR_VERSION=$(echo $BOSH_PRODUCT_VERSION | awk -F '.' '{print $2}' )


export IS_NSX_ENABLED=false
if [ "$BOSH_MAJOR_VERSION" -le 1 ]; then
  if [ "$BOSH_MINOR_VERSION" -ge 11 ]; then
    export IS_NSX_ENABLED=true
  fi
else
  export IS_NSX_ENABLED=true
fi

# Overwrite iaas conf
if [ "$IS_NSX_ENABLED" == "true" ]; then
  cat > /tmp/iaas_conf.txt <<-EOF
{
  "vcenter_host": "$VCENTER_HOST",
  "vcenter_username": "$VCENTER_USR",
  "vcenter_password": "$VCENTER_PWD",
  "datacenter": "$VCENTER_DATA_CENTER",
  "disk_type": "$VCENTER_DISK_TYPE",
  "ephemeral_datastores_string": "$STORAGE_NAMES",
  "persistent_datastores_string": "$STORAGE_NAMES",
  "bosh_vm_folder": "pcf_vms",
  "bosh_template_folder": "pcf_templates",
  "bosh_disk_path": "pcf_disk",
  "ssl_verification_enabled": false,
  "nsx_networking_enabled": true,
  "nsx_address": "${NSX_MANAGER_HOST_ADDRESS}",
  "nsx_username": "${NSX_MANAGER_ADMIN_USER}",
  "nsx_password": "${NSX_MANAGER_ADMIN_PASSWD}",
  "nsx_ca_certificate": "$(cat /tmp/nsx_manager.edited_cert)"
}
EOF
fi

IAAS_CONFIGURATION=$(cat /tmp/iaas_conf.txt)

AZ_CONFIGURATION=$(cat <<-EOF
{
  "availability_zones": [
    {
      "name": "$AZ_1",
      "cluster": "$AZ_1_CUSTER_NAME",
      "resource_pool": "$AZ_1_RP_NAME"
    },
    {
      "name": "$AZ_2",
      "cluster": "$AZ_2_CUSTER_NAME",
      "resource_pool": "$AZ_2_RP_NAME"
    },
    {
      "name": "$AZ_3",
      "cluster": "$AZ_3_CUSTER_NAME",
      "resource_pool": "$AZ_3_RP_NAME"
    }
  ]
}
EOF
)

MY_INFRA_AZS=$(fn_get_azs $INFRA_NW_AZ)
MY_DEPLOYMENT_AZS=$(fn_get_azs $DEPLOYMENT_NW_AZ)
MY_SERVICES_AZS=$(fn_get_azs $SERVICES_NW_AZ)
MY_DYNAMIC_SERVICES_AZS=$(fn_get_azs $DYNAMIC_SERVICES_NW_AZ)
MY_ISOZONE_SWITCH_1_AZS=$(fn_get_azs $ISOZONE_SWITCH_1_NW_AZ)

NETWORK_CONFIGURATION=$(cat <<-EOF
{
  "icmp_checks_enabled": true,
  "networks": [
    {
      "name": "$INFRA_NETWORK_NAME",
      "service_network": false,
      "subnets": [
        {
          "iaas_identifier": "$INFRA_VCENTER_NETWORK",
          "cidr": "$INFRA_NW_CIDR",
          "reserved_ip_ranges": "$INFRA_EXCLUDED_RANGE",
          "dns": "$INFRA_NW_DNS",
          "gateway": "$INFRA_NW_GATEWAY",
          "availability_zone_names": [
            $MY_INFRA_AZS
          ]
        }
      ]
    },
    {
      "name": "$DEPLOYMENT_NETWORK_NAME",
      "service_network": false,
      "subnets": [
        {
          "iaas_identifier": "$DEPLOYMENT_VCENTER_NETWORK",
          "cidr": "$DEPLOYMENT_NW_CIDR",
          "reserved_ip_ranges": "$DEPLOYMENT_EXCLUDED_RANGE",
          "dns": "$DEPLOYMENT_NW_DNS",
          "gateway": "$DEPLOYMENT_NW_GATEWAY",
          "availability_zone_names": [
            $MY_DEPLOYMENT_AZS
          ]
        }
      ]
    },
    {
      "name": "$SERVICES_NETWORK_NAME",
      "service_network": false,
      "subnets": [
        {
          "iaas_identifier": "$SERVICES_VCENTER_NETWORK",
          "cidr": "$SERVICES_NW_CIDR",
          "reserved_ip_ranges": "$SERVICES_EXCLUDED_RANGE",
          "dns": "$SERVICES_NW_DNS",
          "gateway": "$SERVICES_NW_GATEWAY",
          "availability_zone_names": [
            $MY_SERVICES_AZS
          ]
        }
      ]
    },
    {
      "name": "$DYNAMIC_SERVICES_NETWORK_NAME",
      "service_network": true,
      "subnets": [
        {
          "iaas_identifier": "$DYNAMIC_SERVICES_VCENTER_NETWORK",
          "cidr": "$DYNAMIC_SERVICES_NW_CIDR",
          "reserved_ip_ranges": "$DYNAMIC_SERVICES_EXCLUDED_RANGE",
          "dns": "$DYNAMIC_SERVICES_NW_DNS",
          "gateway": "$DYNAMIC_SERVICES_NW_GATEWAY",
          "availability_zone_names": [
            $MY_DYNAMIC_SERVICES_AZS
          ]
        }
      ]
    },
    {
      "name": "$ISOZONE_SWITCH_1_NETWORK_NAME",
      "service_network": false,
      "subnets": [
        {
          "iaas_identifier": "$ISOZONE_SWITCH_1_VCENTER_NETWORK",
          "cidr": "$ISOZONE_SWITCH_CIDR_1",
          "reserved_ip_ranges": "$ISOZONE_SWITCH_1_EXCLUDED_RANGE",
          "dns": "$ISOZONE_SWITCH_1_NW_DNS",
          "gateway": "$ISOZONE_SWITCH_1_NW_GATEWAY",
          "availability_zone_names": [
            $MY_ISOZONE_SWITCH_1_AZS
          ]
        }
      ]
    }
  ]
}
EOF
)

DIRECTOR_CONFIG=$(cat <<-EOF
{
  "ntp_servers_string": "$NTP_SERVER_IPS",
  "metrics_ip": null,
  "resurrector_enabled": true,
  "max_threads": null,
  "database_type": "internal",
  "blobstore_type": "local",
  "director_hostname": "$OPS_DIR_HOSTNAME"
}
EOF
)

NETWORK_ASSIGNMENT=$(cat <<-EOF
{
  "network_and_az": {
     "network": {
       "name": "$INFRA_NETWORK_NAME"
     },
     "singleton_availability_zone": {
       "name": "$AZ_SINGLETON"
     }
  }
}
EOF
)

# OM Cli v0.23.0 does not support nsx related configs
# $CMD -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD configure-bosh \
#.            -i "$IAAS_CONFIGURATION" \
#             -d "$DIRECTOR_CONFIG"

# So post it directly to the ops mgr endpoint
$CMD  -t https://$OPS_MGR_HOST -skip-ssl-validation -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
        curl  -p "/api/v0/staged/director/properties" \
        -x PUT -d "{ \"iaas_configuration\": $IAAS_CONFIGURATION }"
# Check for errors
if [ $? != 0 ]; then
  echo "IaaS configuration failed!!"
  exit 1
fi

$CMD -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD configure-bosh \
            -d "$DIRECTOR_CONFIG"
# Check for errors
if [ $? != 0 ]; then
  echo "Bosh Director configuration failed!!"
  exit 1
fi

$CMD -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
            curl -p "/api/v0/staged/director/availability_zones" \
            -x PUT -d "$AZ_CONFIGURATION"
# Check for errors
if [ $? != 0 ]; then
  echo "Availability Zones configuration failed!!"
  exit 1
fi

$CMD -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
            curl -p "/api/v0/staged/director/networks" \
            -x PUT -d "$NETWORK_CONFIGURATION"
# Check for errors
if [ $? != 0 ]; then
  echo "Networks configuration failed!!"
  exit 1
fi

$CMD -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
            curl -p "/api/v0/staged/director/network_and_az" \
            -x PUT -d "$NETWORK_ASSIGNMENT"
# Check for errors
if [ $? != 0 ]; then
  echo "Network and AZ assignment failed!!"
  exit 1
fi

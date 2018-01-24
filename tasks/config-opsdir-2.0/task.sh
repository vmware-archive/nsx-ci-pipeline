#!/bin/bash

set -eu

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
                  >  /tmp/complete_nsx_manager_cert.log

NSX_MANAGER_CERT_ADDRESS=`cat /tmp/complete_nsx_manager_cert.log \
                        | grep Subject | grep "CN=" \
                        | awk '{print $NF}' \
                        | sed -e 's/CN=//g' `

echo "Fully qualified domain name for NSX Manager: $NSX_MANAGER_FQDN"
echo "Host name associated with NSX Manager cert: $NSX_MANAGER_CERT_ADDRESS"

# Get all certs from the nsx manager
openssl s_client -host $NSX_MANAGER_ADDRESS \
                 -port 443 -prexit -showcerts \
                 </dev/null 2>/dev/null  \
                 >  /tmp/nsx_manager_all_certs.log

# Get the very last CA cert from the showcerts result
cat /tmp/nsx_manager_all_certs.log \
                  |  awk '/BEGIN /,/END / {print }' \
                  | tail -30                        \
                  |  awk '/BEGIN /,/END / {print }' \
                  >  /tmp/nsx_manager_cacert.log

# Strip newlines and replace them with \r\n
cat /tmp/nsx_manager_cacert.log | tr '\n' '#'| sed -e 's/#/\\r\\n/g'   > /tmp/nsx_manager_edited_cacert.log

#CSV parsing Function for mutiple AZs

NSX_CA_CERTIFICATE=$(cat /tmp/nsx_manager_edited_cacert.log)

function fn_get_azs {
     local azs_csv=$1
     echo $azs_csv | awk -F "," -v quote='"' -v OFS='", "' '$1=$1 {print quote $0 quote}'
}

function fn_get_pg {
  local search_string_net=$1
  local search_string="lsw-${NSX_EDGE_GEN_NAME}-${search_string_net}"
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

iaas_configuration=$(
  jq -n \
  --arg vcenter_host "$VCENTER_HOST" \
  --arg vcenter_username "$VCENTER_USR" \
  --arg vcenter_password "$VCENTER_PWD" \
  --arg datacenter "$VCENTER_DATA_CENTER" \
  --arg disk_type "$VCENTER_DISK_TYPE" \
  --arg ephemeral_datastores_string "$EPHEMERAL_STORAGE_NAMES" \
  --arg persistent_datastores_string "$PERSISTENT_STORAGE_NAMES" \
  --arg bosh_vm_folder "$BOSH_VM_FOLDER" \
  --arg bosh_template_folder "$BOSH_TEMPLATE_FOLDER" \
  --arg bosh_disk_path "$BOSH_DISK_PATH" \
  --arg ssl_verification_enabled false \
  --arg nsx_networking_enabled $NSX_NETWORKING_ENABLED \
  --arg nsx_mode "nsx-v" \
  --arg nsx_address "$NSX_MANAGER_FQDN" \
  --arg nsx_username "$NSX_MANAGER_ADMIN_USER" \
  --arg nsx_password "$NSX_MANAGER_ADMIN_PASSWD" \
  --arg nsx_ca_certificate "$NSX_CA_CERTIFICATE" \
  '
  {
    "vcenter_host": $vcenter_host,
    "vcenter_username": $vcenter_username,
    "vcenter_password": $vcenter_password,
    "datacenter": $datacenter,
    "disk_type": $disk_type,
    "ephemeral_datastores_string": $ephemeral_datastores_string,
    "persistent_datastores_string": $persistent_datastores_string,
    "bosh_vm_folder": $bosh_vm_folder,
    "bosh_template_folder": $bosh_template_folder,
    "bosh_disk_path": $bosh_disk_path,
    "ssl_verification_enabled": $ssl_verification_enabled,
    "nsx_networking_enabled": $nsx_networking_enabled,
    "nsx_mode": "$nsx_mode",
    "nsx_address": $nsx_address,
    "nsx_username": $nsx_username,
    "nsx_password": $nsx_password,
    "nsx_ca_certificate": $nsx_ca_certificate
  }'
)

az_configuration=$(cat <<-EOF
{
  "availability_zones": [
    {
      "name": "$AZ_1",
      "cluster": "$AZ_1_CLUSTER_NAME",
      "resource_pool": "$AZ_1_RP_NAME"
    },
    {
      "name": "$AZ_2",
      "cluster": "$AZ_2_CLUSTER_NAME",
      "resource_pool": "$AZ_2_RP_NAME"
    },
    {
      "name": "$AZ_3",
      "cluster": "$AZ_3_CLUSTER_NAME",
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


network_configuration=$(
  jq -n \
    --argjson icmp_checks_enabled $ICMP_CHECKS_ENABLED \
    --arg infra_network_name "$INFRA_NETWORK_NAME" \
    --arg infra_vcenter_network "$INFRA_VCENTER_NETWORK" \
    --arg infra_network_cidr "$INFRA_NW_CIDR" \
    --arg infra_reserved_ip_ranges "$INFRA_EXCLUDED_RANGE" \
    --arg infra_dns "$INFRA_NW_DNS" \
    --arg infra_gateway "$INFRA_NW_GATEWAY" \
    --arg infra_availability_zones "$MY_INFRA_AZS" \
    --arg deployment_network_name "$DEPLOYMENT_NETWORK_NAME" \
    --arg deployment_vcenter_network "$DEPLOYMENT_VCENTER_NETWORK" \
    --arg deployment_network_cidr "$DEPLOYMENT_NW_CIDR" \
    --arg deployment_reserved_ip_ranges "$DEPLOYMENT_EXCLUDED_RANGE" \
    --arg deployment_dns "$DEPLOYMENT_NW_DNS" \
    --arg deployment_gateway "$DEPLOYMENT_NW_GATEWAY" \
    --arg deployment_availability_zones "$MY_DEPLOYMENT_AZS" \
    --arg services_network_name "$SERVICES_NETWORK_NAME" \
    --arg services_vcenter_network "$SERVICES_VCENTER_NETWORK" \
    --arg services_network_cidr "$SERVICES_NW_CIDR" \
    --arg services_reserved_ip_ranges "$SERVICES_EXCLUDED_RANGE" \
    --arg services_dns "$SERVICES_NW_DNS" \
    --arg services_gateway "$SERVICES_NW_GATEWAY" \
    --arg services_availability_zones "$MY_SERVICES_AZS" \
    --arg dynamic_services_network_name "$DYNAMIC_SERVICES_VCENTER_NETWORK" \
    --arg dynamic_services_vcenter_network "$DYNAMIC_SERVICES_VCENTER_NETWORK" \
    --arg dynamic_services_network_cidr "$DYNAMIC_SERVICES_NW_CIDR" \
    --arg dynamic_services_reserved_ip_ranges "$DYNAMIC_SERVICES_EXCLUDED_RANGE" \
    --arg dynamic_services_dns "$DYNAMIC_SERVICES_NW_DNS" \
    --arg dynamic_services_gateway "$DYNAMIC_SERVICES_NW_GATEWAY" \
    --arg dynamic_services_availability_zones "$MY_DYNAMIC_SERVICES_AZS" \
    --arg isozone_switch1_network_name "$ISOZONE_SWITCH_1_VCENTER_NETWORK" \
    --arg isozone_switch1_vcenter_network "$DYNAMIC_SERVICES_VCENTER_NETWORK" \
    --arg isozone_switch1_network_cidr "$ISOZONE_SWITCH_CIDR_1" \
    --arg isozone_switch1_reserved_ip_ranges "$ISOZONE_SWITCH_1_EXCLUDED_RANGE" \
    --arg isozone_switch1_dns "$ISOZONE_SWITCH_1_NW_DNS" \
    --arg isozone_switch1_gateway "$ISOZONE_SWITCH_1_NW_GATEWAY" \
    --arg isozone_switch1_availability_zones "$MY_ISOZONE_SWITCH_1_AZS" \
    '
    {
      "icmp_checks_enabled": $icmp_checks_enabled,
      "networks": [
        {
          "name": $infra_network_name,
          "service_network": false,
          "subnets": [
            {
              "iaas_identifier": $infra_vcenter_network,
              "cidr": $infra_network_cidr,
              "reserved_ip_ranges": $infra_reserved_ip_ranges,
              "dns": $infra_dns,
              "gateway": $infra_gateway,
              "availability_zones": ($infra_availability_zones | split(","))
            }
          ]
        },
        {
          "name": $deployment_network_name,
          "service_network": false,
          "subnets": [
            {
              "iaas_identifier": $deployment_vcenter_network,
              "cidr": $deployment_network_cidr,
              "reserved_ip_ranges": $deployment_reserved_ip_ranges,
              "dns": $deployment_dns,
              "gateway": $deployment_gateway,
              "availability_zones": ($deployment_availability_zones | split(","))
            }
          ]
        },
        {
          "name": $services_network_name,
          "service_network": false,
          "subnets": [
            {
              "iaas_identifier": $services_vcenter_network,
              "cidr": $services_network_cidr,
              "reserved_ip_ranges": $services_reserved_ip_ranges,
              "dns": $services_dns,
              "gateway": $services_gateway,
              "availability_zones": ($services_availability_zones | split(","))
            }
          ]
        },
        {
          "name": $dynamic_services_network_name,
          "service_network": true,
          "subnets": [
            {
              "iaas_identifier": $dynamic_services_vcenter_network,
              "cidr": $dynamic_services_network_cidr,
              "reserved_ip_ranges": $dynamic_services_reserved_ip_ranges,
              "dns": $dynamic_services_dns,
              "gateway": $dynamic_services_gateway,
              "availability_zones": ($dynamic_services_availability_zones | split(","))
            }
          ]
        },
        {
          "name": $isozone_switch1_network_name,
          "service_network": true,
          "subnets": [
            {
              "iaas_identifier": $isozone_switch1_vcenter_network,
              "cidr": $isozone_switch1_network_cidr,
              "reserved_ip_ranges": $isozone_switch1_reserved_ip_ranges,
              "dns": $isozone_switch1_dns,
              "gateway": $isozone_switch1_gateway,
              "availability_zones": ($isozone_switch1_availability_zones | split(","))
            }
          ]
        }
      ]
    }'
)

director_config=$(cat <<-EOF
{
  "ntp_servers_string": "$NTP_SERVER_IPS",
  "resurrector_enabled": $ENABLE_VM_RESURRECTOR,
  "max_threads": $MAX_THREADS,
  "database_type": "internal",
  "blobstore_type": "local",
  "director_hostname": "$OPS_DIR_HOSTNAME"
}
EOF
)

security_configuration=$(
  jq -n \
    --arg trusted_certificates "$TRUSTED_CERTIFICATES" \
    '
    {
      "trusted_certificates": $trusted_certificates,
      "vm_password_type": "generate"
    }'
)

network_assignment=$(
jq -n \
  --arg infra_availability_zones "$MY_INFRA_AZS" \
  --arg network "$INFRA_NETWORK_NAME" \
  '
  {
    "singleton_availability_zone": ($infra_availability_zones | split(",") | .[0]),
    "network": $network
  }'
)

echo "Configuring IaaS and Director..."

# om-linux has issues with handling boolean types 
# wrapped as string for uknown flags like nsx_networking_enabled
# Error: configuring iaas specific options for bosh tile
# could not execute "configure-bosh": 
# could not decode json: 
# json: cannot unmarshal string into Go value of type bool
wrapped_iaas_config=$(cat << EOF
{
   "iaas_configuration" : $iaas_configuration
}
EOF
)

# So split the configure steps into iaas that uses curl to PUT and normal path for director config
$CMD \
  --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  --skip-ssl-validation \
  --username $OPSMAN_USERNAME \
  --password $OPSMAN_PASSWORD \
  curl -p '/api/v0/staged/director/properties' \
  -x PUT -d  "$wrapped_iaas_config"
# Check for errors
if [ $? != 0 ]; then
  echo "IaaS configuration failed!!"
  exit 1
fi

$CMD \
  --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  --skip-ssl-validation \
  --username $OPSMAN_USERNAME \
  --password $OPSMAN_PASSWORD \
  configure-bosh \
  --director-configuration "$director_config"
# Check for errors
if [ $? != 0 ]; then
  echo "Bosh Director configuration failed!!"
  exit 1
fi

$CMD -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -k -u $OPSMAN_USERNAME -p $OPSMAN_PASSWORD \
  curl -p "/api/v0/staged/director/availability_zones" \
  -x PUT -d "$az_configuration"
# Check for errors
if [ $? != 0 ]; then
  echo "Availability Zones configuration failed!!"
  exit 1
fi

$CMD \
  --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  --skip-ssl-validation \
  --username $OPSMAN_USERNAME \
  --password $OPSMAN_PASSWORD \
  configure-bosh \
  --networks-configuration "$network_configuration" \
  --network-assignment "$network_assignment" \
  --security-configuration "$security_configuration"
# Check for errors
if [ $? != 0 ]; then
  echo "Networks configuration and AZ assignemnt failed!!"
  exit 1
fi
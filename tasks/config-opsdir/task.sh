#!/bin/bash
set -e

chmod +x om-cli/om-linux

CMD=./om-cli/om-linux

#CSV parsing Function for mutiple AZs

function fn_get_azs {
     local azs_csv=$1
     echo $azs_csv | awk -F "," -v quote='"' -v OFS='", "' '$1=$1 {print quote $0 quote}'
}

function fn_get_pg {
  local search_string_net=$1
  local search_string="lswitch-${NSX_EDGE_GEN_NAME}-${search_string_net}"
  vwire_pg=$(
  ./nsx-gen/bin/nsxgen \
  -c $NSX_EDGE_GEN_NAME \
  -vcenter_addr $VCENTER_HOST   \
  -vcenter_user $VCENTER_USR   \
  -vcenter_pass $VCENTER_PWD   \
  -vcenter_dc $VCENTER_DATA_CENTER   \
  -vcenter_ds $NSX_EDGE_GEN_EDGE_DATASTORE   \
  -vcenter_cluster $NSX_EDGE_GEN_EDGE_CLUSTER  \
  -nsxmanager_addr $NSX_EDGE_GEN_NSX_MANAGER_ADDRESS   \
  -nsxmanager_user $NSX_EDGE_GEN_NSX_MANAGER_ADMIN_USER   \
  -nsxmanager_pass $NSX_EDGE_GEN_NSX_MANAGER_ADMIN_PASSWD   \
  -nsxmanager_tz $NSX_EDGE_GEN_NSX_MANAGER_TRANSPORT_ZONE   \
  -nsxmanager_dportswitch $NSX_EDGE_GEN_NSX_MANAGER_DISTRIBUTED_PORT_SWITCH \
  -nsxmanager_uplink_ip 172.16.0.0 \
  list 2>/dev/null | \
  grep ${search_string} | \
  grep -v "Effective" | awk '{print$5}' |  grep "virtualwire" | sort -u
  )
  echo $vwire_pg
}

IAAS_CONFIGURATION=$(cat <<-EOF
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
)

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

echo "Detecting NSX Logical Switch Backing Port Groups..."
  pushd nsx-edge-gen >/dev/null 2>&1
  if [[ -e nsx_cloud_config.yml ]]; then rm -rf nsx_cloud_config.yml; fi
  ./nsx-gen/bin/nsxgen -i $NSX_EDGE_GEN_NAME init
  if [[ $INFRA_VCENTER_NETWORK = "nsxgen" ]]; then export INFRA_VCENTER_NETWORK=$(fn_get_pg "Infra"); echo "Found $INFRA_VCENTER_NETWORK"; fi
  if [[ $DEPLOYMENT_VCENTER_NETWORK = "nsxgen" ]]; then export DEPLOYMENT_VCENTER_NETWORK=$(fn_get_pg "Ert"); echo "Found $DEPLOYMENT_VCENTER_NETWORK"; fi
  if [[ $SERVICES_VCENTER_NETWORK = "nsxgen" ]]; then export SERVICES_VCENTER_NETWORK=$(fn_get_pg "PCF-Tiles"); echo "Found $SERVICES_VCENTER_NETWORK"; fi
  if [[ $DYNAMIC_SERVICES_VCENTER_NETWORK = "nsxgen" ]]; then export DYNAMIC_SERVICES_VCENTER_NETWORK=$(fn_get_pg "Dynamic-Services"); echo "Found $DYNAMIC_SERVICES_VCENTER_NETWORK"; fi
  if [[ $ISOZONE_SWITCH_1_VCENTER_NETWORK = "nsxgen" ]]; then export ISOZONE_SWITCH_1_VCENTER_NETWORK=$(fn_get_pg "IsoZone-01"); echo "Found $ISOZONE_SWITCH_1_VCENTER_NETWORK"; fi
  popd >/dev/null 2>&1


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
          "iaas_identifier": "$ISOZONE_SWITCH_1_VSPHERE_NETWORK",
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

$CMD -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD configure-bosh \
            -i "$IAAS_CONFIGURATION" \
            -d "$DIRECTOR_CONFIG"

$CMD -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
            curl -p "/api/v0/staged/director/availability_zones" \
            -x PUT -d "$AZ_CONFIGURATION"

$CMD -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
            curl -p "/api/v0/staged/director/networks" \
            -x PUT -d "$NETWORK_CONFIGURATION"

$CMD -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
            curl -p "/api/v0/staged/director/network_and_az" \
            -x PUT -d "$NETWORK_ASSIGNMENT"

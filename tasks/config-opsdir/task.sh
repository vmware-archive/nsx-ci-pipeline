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

SECURITY_CONFIGURATION=$(cat <<-EOF
{
  "security_configuration": {
    "generate_vm_passwords": true,
    "trusted_certificates": "-----BEGIN CERTIFICATE-----\nMIIDRTCCAi2gAwIBAgIJANs4R2E1xj1nMA0GCSqGSIb3DQEBCwUAMCAxHjAcBgNV\nBAMTFTE5Mi4xNjguMTAuMTUtUk9PVC1DQTAeFw0xNzA2MDIyMDA5MDFaFw0yNzA1\nMzEyMDA5MDFaMCAxHjAcBgNVBAMTFTE5Mi4xNjguMTAuMTUtUk9PVC1DQTCCASIw\nDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMK0oHaBIw62Kx/bisAiD00r5/Q0\n46Vz7UssHzmkl1dROMCpCtKC3Tnk8GNwj8U9wLk7eSlVIZRBvX9XT4+VIms1laOj\nMEThBvB9oRb97LD4m6DdS6bKDG/NAFgmLPYSfWPhR4et+FgDQN5tzbPPqBjG+JY6\nHt+C7DK/KIZuOXkRLNKSkkJ0VElZeKZjQihybvAmHiNeL2Smc8wrvrxgZlVOyUpH\nV/XIjpx0Gka4u2b+N3/+b8DFTziFLFyz6dYjtbENpHrDz33QdPpBV9YdVuoA8bhw\nCgsSBMSEhfhbx0N2AwMRUKHqWg6ClKXoqxZnsk8l/zKNTR4CWNcJELgIoNUCAwEA\nAaOBgTB/MB0GA1UdDgQWBBQUZawBghOS8/WlH1RfFaa/MwSDFjBQBgNVHSMESTBH\ngBQUZawBghOS8/WlH1RfFaa/MwSDFqEkpCIwIDEeMBwGA1UEAxMVMTkyLjE2OC4x\nMC4xNS1ST09ULUNBggkA2zhHYTXGPWcwDAYDVR0TBAUwAwEB/zANBgkqhkiG9w0B\nAQsFAAOCAQEALXn3VzNIcjaQfGzwR2fgzBTQfmVy/JCTSTMPb1fr0zjb8zNKu64o\n6y9PSidNtTPCxQwOnOojReaeIv9o8n3a2rwOCmtP9PSup2Th2sBeq6djqK5qrouJ\n4SAvtf9GpQiIFx8m9cvFFAosNnlU+8g2O6qRrt+rAu5+qs5EMdjgVgDDxO5pnZXt\no2+1zYlh+YNH/SaPdruzPd3JVYw2f0ScDwmb5xBO+RaT36pSh7DeUbbtb/K4fMbl\noVRSjP0cKZwVL5QSwQ42s3KQBDV4RlOkUmFljESJXX5a+7+mJe2riVwfNrRFL5bR\n6r9377Ahp7FSjJBrq0Ht/IqXIaZPYVgvjA==\n-----END CERTIFICATE-----\n"
  }
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

if [ "$INFRA_OPS_STATIC_IPS" == "" \
  -o "$ERT_GOROUTER_STATIC_IPS" == "" \
  -o "$ERT_TCPROUTER_STATIC_IPS" == "" \
  -o "$SSH_STATIC_IPS" ==  "" \
  -o "$ERT_MYSQL_STATIC_IPS" == "" \
  -o "$MYSQL_TILE_STATIC_IPS" == ""  \
  -o "$RABBITMQ_TILE_STATIC_IPS" == "" ]; then 
  echo "Some of the static ips could not be located from NSX!!"
  echo "  Found static ip  for INFRA Ops              : $INFRA_OPS_STATIC_IPS"
  echo "  Found static ips for ERT GoRouter           : $ERT_GOROUTER_STATIC_IPS"
  echo "  Found static ips for ERT TcpRouter          : $ERT_TCPROUTER_STATIC_IPS"
  echo "  Found static ips for ERT Diego Brain        : $SSH_STATIC_IPS"
  echo "  Found static ips for ERT MySQL              : $ERT_MYSQL_STATIC_IPS"
  echo "  Found static ips for SERVICES MySQL Tile    : $MYSQL_TILE_STATIC_IPS"
  echo "  Found static ips for SERVICES RabbitMQ Tile : $RABBITMQ_TILE_STATIC_IPS"
  exit 1
fi

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

$CMD -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD configure-bosh \
            -i "$IAAS_CONFIGURATION" \
            -d "$DIRECTOR_CONFIG"

# Check for errors
if [ $? != 0 ]; then
  echo "Bosh Director configuration failed!!"
  exit 1
fi

echo "Configuring Harbor Registry security..."
$CMD -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
  curl -p "/api/v0/staged/director/properties" \
  -x PUT -d "$SECURITY_CONFIG"

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

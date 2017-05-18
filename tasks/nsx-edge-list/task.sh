#!/bin/bash
set -e


pushd nsx-edge-gen  >/dev/null 2>&1

mkdir -p ../nsx-gen-output
export NSX_FILE_OUTPUT=../nsx-gen-output/nsx-gen-out.log

# Remove any existing config file template from the repo
if [[ -e nsx_cloud_config.yml ]]; then rm -rf nsx_cloud_config.yml; fi


# Init new config file template
./nsx-gen/bin/nsxgen -i $NSX_EDGE_GEN_NAME init

if [[ ISOZONE_SWITCH_NAME_1 ]]; then
  ARGS="
  -isozone_switch_name_1 $ISOZONE_SWITCH_NAME_1
  -isozone_switch_cidr_1 $ISOZONE_SWITCH_CIDR_1
  -esg_go_router_isozone_1_uplink_ip_1 $ESG_GO_ROUTER_ISOZONE_1_UPLINK_IP_1
  -esg_go_router_isozone_1_switch_1 $ISOZONE_SWITCH_NAME_1
  -esg_go_router_isozone_1_inst_1 $ESG_GO_ROUTER_ISOZONE_1_INST_1
  -esg_tcp_router_isozone_1_uplink_ip_1 $ESG_TCP_ROUTER_ISOZONE_1_UPLINK_IP_1 
  -esg_tcp_router_isozone_1_switch_1 $ISOZONE_SWITCH_NAME_1
  -esg_tcp_router_isozone_1_inst_1 $ESG_TCP_ROUTER_ISOZONE_1_INST_1
  "
fi

./nsx-gen/bin/nsxgen \
-c $NSX_EDGE_GEN_NAME \
-esg_name_1 $NSX_EDGE_GEN_NAME \
-esg_ospf_password_1 $ESG_OSPF_PASSWORD_1  \
-esg_cli_user_1 $ESG_CLI_USERNAME_1   \
-esg_cli_pass_1 $ESG_CLI_PASSWORD_1   \
-esg_certs_1 $ESG_CERTS_NAME_1   \
-esg_certs_config_sysd_1 $ESG_CERTS_CONFIG_SYSTEMDOMAIN_1   \
-esg_certs_config_appd_1 $ESG_CERTS_CONFIG_APPDOMAIN_1   \
-esg_opsmgr_uplink_ip_1 $ESG_OPSMGR_UPLINK_IP_1   \
-esg_go_router_uplink_ip_1 $ESG_GO_ROUTER_UPLINK_IP_1   \
-esg_diego_brain_uplink_ip_1 $ESG_DIEGO_BRAIN_UPLINK_IP_1   \
-esg_tcp_router_uplink_ip_1 $ESG_TCP_ROUTER_UPLINK_IP_1   \
-esg_gateway_1 $ESG_GATEWAY_1 \
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
-nsxmanager_dportgroup $NSX_EDGE_GEN_NSX_MANAGER_DISTRIBUTED_PORTGROUP \
-nsxmanager_uplink_ip $ESG_DEFAULT_UPLINK_IP_1  \
-nsxmanager_uplink_port "$ESG_DEFAULT_UPLINK_PG_1" \
$ARGS \
list | tee $NSX_FILE_OUTPUT 2>&1 

function fn_get_pg {
  local nsx_log=$1
  local search_string_net=$2
  local search_string="lswitch-${NSX_EDGE_GEN_NAME}-${search_string_net}"
  vwire_pg=$(
  cat ${nsx_log} | \
  grep ${search_string} | \
  grep -v "Effective" | awk '{print$5}' |  grep "virtualwire" | sort -u
  )
  echo $vwire_pg
}

function fn_get_component_static_ips {
  local nsx_log=$1
  local search_switch=$2
  local search_component=$3
  component_static_ips=$(
  cat ${nsx_log} | \
   grep  "static ips" |
   grep ${search_switch} | \
   grep ${search_component} | \
   awk -F '|' '{print$5}' 
  )
  echo $component_static_ips
}

if [ -e "$NSX_FILE_OUTPUT" ]; then
  echo "Saved nsx gen output:"
cat $NSX_FILE_OUTPUT
else
  echo "Unable to retreive nsx gen output!!"
  exit 1
fi

echo "Detecting NSX Logical Switch Backing Port Groups..."

export INFRA_VCENTER_NETWORK=$(fn_get_pg "$NSX_FILE_OUTPUT" "Infra")
export DEPLOYMENT_VCENTER_NETWORK=$(fn_get_pg "$NSX_FILE_OUTPUT" "Ert")
export SERVICES_VCENTER_NETWORK=$(fn_get_pg "$NSX_FILE_OUTPUT" "PCF-Tiles")
export DYNAMIC_SERVICES_VCENTER_NETWORK=$(fn_get_pg "$NSX_FILE_OUTPUT" "Dynamic-Services")
export OPS_INFRA_STATIC_IPS=$(fn_get_static_ips "$NSX_FILE_OUTPUT" "Infra" "ops")
export GOROUTER_ERT_STATIC_IPS=$(fn_get_static_ips "$NSX_FILE_OUTPUT" "Ert" "go-router")
export TCP_ROUTER_ERT_STATIC_IPS=$(fn_get_static_ips "$NSX_FILE_OUTPUT" "Ert" "tcp-router")
export SSH_ERT_STATIC_IPS=$(fn_get_static_ips "$NSX_FILE_OUTPUT" "Ert" "diego-brain")
export MYSQL_ERT_STATIC_IPS=$(fn_get_static_ips "$NSX_FILE_OUTPUT" "Ert" "mysql")
export MYSQL_TILE_STATIC_IPS=$(fn_get_static_ips "$NSX_FILE_OUTPUT" "PCF-Tiles" "mysql")
export RABBITMQ_TILE_STATIC_IPS=$(fn_get_static_ips "$NSX_FILE_OUTPUT" "PCF-Tiles" "rabbitmq")

echo "Found $INFRA_VCENTER_NETWORK"
echo "Found $DEPLOYMENT_VCENTER_NETWORK"
echo "Found $SERVICES_VCENTER_NETWORK"
echo "Found $DYNAMIC_SERVICES_VCENTER_NETWORK"
echo ""
echo "Found Ops Infra static ip: $OPS_INFRA_STATIC_IPS"
echo "Found GoRouter Ert static ips: $GOROUTER_ERT_STATIC_IPS"
echo "Found TcpRouter Ert static ips: $TCP_ROUTER_ERT_STATIC_IPS"
echo "Found Diego Brain Ert static ips: $SSH_ERT_STATIC_IPS"
echo "Found MySQL Ert static ips: $MYSQL_ERT_STATIC_IPS"
echo "Found MySQL Tile static ips: $MYSQL_TILE_STATIC_IPS"
echo "Found RabbitMQ Tile static ips: $RABBITMQ_TILE_STATIC_IPS"

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

if [[ ISOZONE_SWITCH_NAME_1 ]]; then
  export ISOZONE_SWITCH_1_VCENTER_NETWORK=$(fn_get_pg "$NSX_FILE_OUTPUT" "IsoZone-1")
  echo "Found $ISOZONE_SWITCH_1_VCENTER_NETWORK"
  
  export GOROUTER_ISOZONE_SWITCH_1_STATIC_IPS=$(fn_get_static_ips "$NSX_FILE_OUTPUT" "IsoZone-1" "go-router")
  echo "Found GoRouter IsoZone static ip: $GOROUTER_ISOZONE_SWITCH_1_STATIC_IPS"
  
  export TCPROUTER_ISOZONE_SWITCH_1_STATIC_IPS=$(fn_get_static_ips "$NSX_FILE_OUTPUT" "IsoZone-1" "tcp-router")
  echo "Found TcpRouter IsoZone static ip: $TCPROUTER_ISOZONE_SWITCH_1_STATIC_IPS"

  if [ "$ISOZONE_SWITCH_1_VCENTER_NETWORK" == "" ]; then
    echo "ISOZONE-01 network could not be located from NSX!!"
  fi
fi


popd  >/dev/null 2>&1

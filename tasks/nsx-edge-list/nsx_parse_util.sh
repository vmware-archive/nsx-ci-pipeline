#!/bin/bash

export NSX_GEN_FILE_OUTPUT=$1
if [ -e "$NSX_GEN_FILE_OUTPUT" ]; then
  echo "Found nsx gen output"
  #cat $NSX_GEN_FILE_OUTPUT
else
  echo "Unable to retreive nsx gen output generated from previous nsx-gen-list task!!"
  exit 1
fi

function fn_get_pg {
  local nsx_log=$1
  local search_string_net=$2
  local search_string="lswitch-${NSX_EDGE_GEN_NAME}-${search_string_net}"
  vwire_pg=$(
  cat ${nsx_log} | \
  grep -i ${search_string} | \
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
   grep -i "static ips assig" |
   grep -i ${search_switch} | \
   grep -i ${search_component} | \
   awk -F '|' '{print$5}' 
  )
  echo $component_static_ips
}

echo "Detecting NSX Logical Switch Backing Port Groups..."

if [[ $INFRA_VCENTER_NETWORK = "nsxgen" ]]; then export INFRA_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_FILE_OUTPUT" "Infra"); fi
if [[ $DEPLOYMENT_VCENTER_NETWORK = "nsxgen" ]]; then export DEPLOYMENT_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_FILE_OUTPUT" "Ert"); fi
if [[ $SERVICES_VCENTER_NETWORK = "nsxgen" ]]; then export SERVICES_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_FILE_OUTPUT" "PCF-Tiles"); fi
if [[ $DYNAMIC_SERVICES_VCENTER_NETWORK = "nsxgen" ]]; then export DYNAMIC_SERVICES_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_FILE_OUTPUT" "Dynamic-Services"); fi
echo "Found INFRASTRUCTURE   : $INFRA_VCENTER_NETWORK"
echo "Found ERT DEPLOYMENT   : $DEPLOYMENT_VCENTER_NETWORK"
echo "Found SERVICES         : $SERVICES_VCENTER_NETWORK"
echo "Found DYNAMIC SERVICES : $DYNAMIC_SERVICES_VCENTER_NETWORK"
echo ""

# Check for Errors with obtaining the networks
if [ "$INFRA_VCENTER_NETWORK" == "" \
  -o "$DEPLOYMENT_VCENTER_NETWORK" == "" \
  -o "$SERVICES_VCENTER_NETWORK" == "" \
  -o "$DYNAMIC_SERVICES_VCENTER_NETWORK" == "" ]; then 
  echo "Some networks could not be located from NSX!!"
  exit 1
fi

export INFRA_OPS_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "Infra" "ops")
export ERT_GOROUTER_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "Ert" "go-router")
export ERT_TCPROUTER_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "Ert" "tcp-router")
export SSH_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "Ert" "diego-brain")
export ERT_MYSQL_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "Ert" "mysql")
export MYSQL_TILE_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "PCF-Tiles" "mysql")
export RABBITMQ_TILE_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "PCF-Tiles" "rabbitmq")

echo "Found INFRA Ops static ip                 : $INFRA_OPS_STATIC_IPS"
echo "Found ERT GoRouter static ips             : $ERT_GOROUTER_STATIC_IPS"
echo "Found ERT TcpRouter static ips            : $ERT_TCPROUTER_STATIC_IPS"
echo "Found ERT Diego Brain static ips          : $SSH_STATIC_IPS"
echo "Found ERT MySQL static ips                : $ERT_MYSQL_STATIC_IPS"
echo "Found SERVICES MySQL Tile static ips      : $MYSQL_TILE_STATIC_IPS"
echo "Found SERVICES RabbitMQ Tile static ips   : $RABBITMQ_TILE_STATIC_IPS"
echo ""

if [[ ISOZONE_SWITCH_NAME_1 ]]; then
  export ISOZONE_SWITCH_1_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_FILE_OUTPUT" "IsoZone-01")
  if [ "$ISOZONE_SWITCH_1_VCENTER_NETWORK" == "" ]; then
    echo "ISOZONE-01 network could not be located from NSX!!"
  fi
  
  export ISOZONE_SWITCH_1_GOROUTER_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "IsoZone-01" "go-router")
  export ISOZONE_SWITCH_1_TCPROUTER_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "IsoZone-01" "tcp-router")

  echo "Found ISOZONE-01                     : $ISOZONE_SWITCH_1_VCENTER_NETWORK"
  echo "Found ISOZONE-01 GoRouter static ip  : $ISOZONE_SWITCH_1_GOROUTER_STATIC_IPS"
  echo "Found ISOZONE-01 TcpRouter static ip : $ISOZONE_SWITCH_1_TCPROUTER_STATIC_IPS"

fi
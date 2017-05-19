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

function fn_get_component_lb_ip {
  local nsx_log=$1
  local search_switch=$2
  local search_component=$3
  component_static_ips=$(
  cat ${nsx_log} | \
   grep -i "static ips assig" |
   grep -i ${search_switch} | \
   grep -i ${search_component} | \
   awk -F '|' '{print$4}' 
  )
  echo $component_lbr_ip
}


echo "Detecting NSX Logical Switch Backing Port Groups..."

export INFRA_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_FILE_OUTPUT" "Infra")
export DEPLOYMENT_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_FILE_OUTPUT" "Ert")
export SERVICES_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_FILE_OUTPUT" "PCF-Tiles")
export DYNAMIC_SERVICES_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_FILE_OUTPUT" "Dynamic-Services")
echo ""
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
fi

export INFRA_OPS_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_FILE_OUTPUT" "Infra" "ops")
export ERT_GOROUTER_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_FILE_OUTPUT" "Ert" "go-router")
export ERT_TCPROUTER_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_FILE_OUTPUT" "Ert" "tcp-router")
export SSH_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_FILE_OUTPUT" "Ert" "diego-brain")
export ERT_MYSQL_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_FILE_OUTPUT" "Ert" "mysql")
export MYSQL_TILE_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_FILE_OUTPUT" "PCF-Tiles" "mysql")
export RABBITMQ_TILE_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_FILE_OUTPUT" "PCF-Tiles" "rabbitmq")

echo ""
echo "Found LBR ip for INFRA    Ops           : $INFRA_OPS_LBR_IP"
echo "Found LBR ip for ERT      GoRouter      : $ERT_GOROUTER_LBR_IP"
echo "Found LBR ip for ERT      TcpRouter     : $ERT_TCPROUTER_LBR_IP"
echo "Found LBR ip for ERT      Diego Brain   : $SSH_LBR_IP"
echo "Found LBR ip for ERT      MySQL         : $ERT_MYSQL_LBR_IP"
echo "Found LBR ip for SERVICES MySQL Tile    : $MYSQL_TILE_LBR_IP"
echo "Found LBR ip for SERVICES RabbitMQ Tile : $RABBITMQ_TILE_LBR_IP"
echo ""

export INFRA_OPS_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "Infra" "ops")
export ERT_GOROUTER_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "Ert" "go-router")
export ERT_TCPROUTER_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "Ert" "tcp-router")
export SSH_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "Ert" "diego-brain")
export ERT_MYSQL_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "Ert" "mysql")
export MYSQL_TILE_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "PCF-Tiles" "mysql")
export RABBITMQ_TILE_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "PCF-Tiles" "rabbitmq")

echo ""
echo "Found Static ip  for INFRA    Ops           : $INFRA_OPS_STATIC_IPS"
echo "Found Static ips for ERT      GoRouter      : $ERT_GOROUTER_STATIC_IPS"
echo "Found Static ips for ERT      TcpRouter     : $ERT_TCPROUTER_STATIC_IPS"
echo "Found Static ips for ERT      Diego Brain   : $SSH_STATIC_IPS"
echo "Found Static ips for ERT      MySQL         : $ERT_MYSQL_STATIC_IPS"
echo "Found Static ips for SERVICES MySQL Tile    : $MYSQL_TILE_STATIC_IPS"
echo "Found Static ips for SERVICES RabbitMQ Tile : $RABBITMQ_TILE_STATIC_IPS"
echo ""

if [[ ISOZONE_SWITCH_NAME_1 ]]; then
  export ISOZONE_SWITCH_1_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_FILE_OUTPUT" "IsoZone-01")
  if [ "$ISOZONE_SWITCH_1_VCENTER_NETWORK" == "" ]; then
    echo "ISOZONE-01 network could not be located from NSX!!"
  fi
  
  export ISOZONE_SWITCH_1_GOROUTER_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "IsoZone-01" "go-router")
  export ISOZONE_SWITCH_1_TCPROUTER_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_FILE_OUTPUT" "IsoZone-01" "tcp-router")
  export ISOZONE_SWITCH_1_GOROUTER_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_FILE_OUTPUT" "IsoZone-01" "go-router")
  export ISOZONE_SWITCH_1_TCPROUTER_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_FILE_OUTPUT" "IsoZone-01" "tcp-router")

  echo "Found ISOZONE-01                          : $ISOZONE_SWITCH_1_VCENTER_NETWORK"
  echo ""
  echo "Found LBR    ip  for ISOZONE-01 GoRouter  : $ISOZONE_SWITCH_1_GOROUTER_LBR_IP"
  echo "Found Static ips for ISOZONE-01 GoRouter  : $ISOZONE_SWITCH_1_GOROUTER_STATIC_IPS"
  echo "Found LBR    ip  for ISOZONE-01 TcpRouter : $ISOZONE_SWITCH_1_TCPROUTER_LBR_IP"
  echo "Found Static ips for ISOZONE-01 TcpRouter : $ISOZONE_SWITCH_1_TCPROUTER_STATIC_IPS"
  echo ""
fi

export NSX_GEN_OUTPUT=$1
if [ -e "$NSX_FILE_OUTPUT" ]; then
  echo "Found nsx gen output:"
  cat $NSX_FILE_OUTPUT
else
  echo "Unable to retreive nsx gen output!!"
  exit 1
fi

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



echo "Detecting NSX Logical Switch Backing Port Groups..."

export INFRA_VCENTER_NETWORK=$(fn_get_pg "$NSX_FILE_OUTPUT" "Infra")
export DEPLOYMENT_VCENTER_NETWORK=$(fn_get_pg "$NSX_FILE_OUTPUT" "Ert")
export SERVICES_VCENTER_NETWORK=$(fn_get_pg "$NSX_FILE_OUTPUT" "PCF-Tiles")
export DYNAMIC_SERVICES_VCENTER_NETWORK=$(fn_get_pg "$NSX_FILE_OUTPUT" "Dynamic-Services")

export OPS_INFRA_STATIC_IPS=$(fn_get_component_static_ips "$NSX_FILE_OUTPUT" "Infra" "ops")
export GOROUTER_ERT_STATIC_IPS=$(fn_get_component_static_ips "$NSX_FILE_OUTPUT" "Ert" "go-router")
export TCP_ROUTER_ERT_STATIC_IPS=$(fn_get_component_static_ips "$NSX_FILE_OUTPUT" "Ert" "tcp-router")
export SSH_ERT_STATIC_IPS=$(fn_get_component_static_ips "$NSX_FILE_OUTPUT" "Ert" "diego-brain")
export MYSQL_ERT_STATIC_IPS=$(fn_get_component_static_ips "$NSX_FILE_OUTPUT" "Ert" "mysql")
export MYSQL_TILE_STATIC_IPS=$(fn_get_component_static_ips "$NSX_FILE_OUTPUT" "PCF-Tiles" "mysql")
export RABBITMQ_TILE_STATIC_IPS=$(fn_get_component_static_ips "$NSX_FILE_OUTPUT" "PCF-Tiles" "rabbitmq")

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
  export ISOZONE_SWITCH_1_VCENTER_NETWORK=$(fn_get_pg "$NSX_FILE_OUTPUT" "IsoZone-01")
  echo "Found $ISOZONE_SWITCH_1_VCENTER_NETWORK"
  
  export GOROUTER_ISOZONE_SWITCH_1_STATIC_IPS=$(fn_get_component_static_ips "$NSX_FILE_OUTPUT" "IsoZone-01" "go-router")
  echo "Found GoRouter IsoZone static ip: $GOROUTER_ISOZONE_SWITCH_1_STATIC_IPS"
  
  export TCPROUTER_ISOZONE_SWITCH_1_STATIC_IPS=$(fn_get_component_static_ips "$NSX_FILE_OUTPUT" "IsoZone-01" "tcp-router")
  echo "Found TcpRouter IsoZone static ip: $TCPROUTER_ISOZONE_SWITCH_1_STATIC_IPS"

  if [ "$ISOZONE_SWITCH_1_VCENTER_NETWORK" == "" ]; then
    echo "ISOZONE-01 network could not be located from NSX!!"
  fi
fi
#!/bin/bash

export NSX_GEN_OUTPUT=$1
if [ -e "$NSX_GEN_OUTPUT" ]; then
  echo "Found nsx gen output"
  #cat $NSX_GEN_OUTPUT
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

function fn_get_component_lbr_ip {
  local nsx_log=$1
  local search_switch=$2
  local search_component=$3
  component_lbr_ip=$(
  cat ${nsx_log} | \
   grep -i "static ips assig" |
   grep -i ${search_switch} | \
   grep -i ${search_component} | \
   awk -F '|' '{print$4}' 
  )
  echo $component_lbr_ip
}

function fn_get_component_pool_details {
  local nsx_log=$1
  local search_switch=$2
  local search_component=$3
  component_lbr_ip=$(
  cat ${nsx_log} | \
   grep -i "lbr assignment" |
   grep -i ${search_switch} | \
   grep -i ${search_component} | \
   awk -F '|' '{print$3":"$5":"$6":"$7":"$8}' | sed -e 's/ //g'
  )
  echo $component_lbr_ip
}

echo "Detecting NSX Logical Switch Backing Port Groups..."

export INFRA_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_OUTPUT" "Infra")
export DEPLOYMENT_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_OUTPUT" "Ert")
export SERVICES_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_OUTPUT" "PCF-Tiles")
export DYNAMIC_SERVICES_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_OUTPUT" "Dynamic-Services")

echo ""
echo "Found INFRASTRUCTURE   Virtual Switch : $INFRA_VCENTER_NETWORK"
echo "Found ERT DEPLOYMENT   Virtual Switch : $DEPLOYMENT_VCENTER_NETWORK"
echo "Found SERVICES         Virtual Switch : $SERVICES_VCENTER_NETWORK"
echo "Found DYNAMIC SERVICES Virtual Switch : $DYNAMIC_SERVICES_VCENTER_NETWORK"
echo ""

# Check for Errors with obtaining the networks
if [ "$INFRA_VCENTER_NETWORK" == "" \
  -o "$DEPLOYMENT_VCENTER_NETWORK" == "" \
  -o "$SERVICES_VCENTER_NETWORK" == "" \
  -o "$DYNAMIC_SERVICES_VCENTER_NETWORK" == "" ]; then 
  echo "Some networks could not be located from NSX!!"
fi

export INFRA_OPS_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_OUTPUT" "Infra" "ops")
export ERT_GOROUTER_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_OUTPUT" "Ert" "go-router")
export ERT_TCPROUTER_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_OUTPUT" "Ert" "tcp-router")
export SSH_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_OUTPUT" "Ert" "diego-brain")
export ERT_MYSQL_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_OUTPUT" "Ert" "mysql")
export MYSQL_TILE_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_OUTPUT" "PCF-Tiles" "mysql")
export RABBITMQ_TILE_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_OUTPUT" "PCF-Tiles" "rabbitmq")

echo ""
echo "Found LBR IP for INFRA    Ops           : $INFRA_OPS_LBR_IP"
echo "Found LBR IP for ERT      GoRouter      : $ERT_GOROUTER_LBR_IP"
echo "Found LBR IP for ERT      TcpRouter     : $ERT_TCPROUTER_LBR_IP"
echo "Found LBR IP for ERT      Diego Brain   : $SSH_LBR_IP"
echo "Found LBR IP for ERT      MySQL         : $ERT_MYSQL_LBR_IP"
echo "Found LBR IP for SERVICES MySQL Tile    : $MYSQL_TILE_LBR_IP"
echo "Found LBR IP for SERVICES RabbitMQ Tile : $RABBITMQ_TILE_LBR_IP"
echo ""

export INFRA_OPS_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_OUTPUT" "Infra" "ops")
export ERT_GOROUTER_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_OUTPUT" "Ert" "go-router")
export ERT_TCPROUTER_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_OUTPUT" "Ert" "tcp-router")
export SSH_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_OUTPUT" "Ert" "diego-brain")
export ERT_MYSQL_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_OUTPUT" "Ert" "mysql")
export MYSQL_TILE_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_OUTPUT" "PCF-Tiles" "mysql")
export RABBITMQ_TILE_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_OUTPUT" "PCF-Tiles" "rabbitmq")

echo ""
echo "Found Static IP  for INFRA    Ops           : $INFRA_OPS_STATIC_IPS"
echo "Found Static IPs for ERT      GoRouter      : $ERT_GOROUTER_STATIC_IPS"
echo "Found Static IPs for ERT      TcpRouter     : $ERT_TCPROUTER_STATIC_IPS"
echo "Found Static IPs for ERT      Diego Brain   : $SSH_STATIC_IPS"
echo "Found Static IPs for ERT      MySQL         : $ERT_MYSQL_STATIC_IPS"
echo "Found Static IPs for SERVICES MySQL Tile    : $MYSQL_TILE_STATIC_IPS"
echo "Found Static IPs for SERVICES RabbitMQ Tile : $RABBITMQ_TILE_STATIC_IPS"
echo ""

export INFRA_OPS_LBR_DETAILS=$(fn_get_component_pool_details "$NSX_GEN_OUTPUT" "Infra" "ops")
export ERT_GOROUTER_LBR_DETAILS=$(fn_get_component_pool_details "$NSX_GEN_OUTPUT" "Ert" "go-router")
export ERT_TCPROUTER_LBR_DETAILS=$(fn_get_component_pool_details "$NSX_GEN_OUTPUT" "Ert" "tcp-router")
export SSH_LBR_DETAILS=$(fn_get_component_pool_details "$NSX_GEN_OUTPUT" "Ert" "diego-brain")
export ERT_MYSQL_LBR_DETAILS=$(fn_get_component_pool_details "$NSX_GEN_OUTPUT" "Ert" "mysql")
export MYSQL_TILE_LBR_DETAILS=$(fn_get_component_pool_details "$NSX_GEN_OUTPUT" "PCF-Tiles" "mysql")
export RABBITMQ_TILE_LBR_DETAILS=$(fn_get_component_pool_details "$NSX_GEN_OUTPUT" "PCF-Tiles" "rabbitmq")

echo ""
echo "Found LBR Details for INFRA    Ops           : $INFRA_OPS_LBR_DETAILS"
echo "Found LBR Details for ERT      GoRouter      : $ERT_GOROUTER_LBR_DETAILS"
echo "Found LBR Details for ERT      TcpRouter     : $ERT_TCPROUTER_LBR_DETAILS"
echo "Found LBR Details for ERT      Diego Brain   : $SSH_LBR_DETAILS"
echo "Found LBR Details for ERT      MySQL         : $ERT_MYSQL_LBR_DETAILS"
echo "Found LBR Details for SERVICES MySQL Tile    : $MYSQL_TILE_LBR_DETAILS"
echo "Found LBR Details for SERVICES RabbitMQ Tile : $RABBITMQ_TILE_LBR_DETAILS"
echo ""

export ISOZONE_SWITCH_1_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_OUTPUT" "IsoZone-01")
export ISOZONE_SWITCH_1_GOROUTER_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_OUTPUT" "IsoZone-01" "go-router")
export ISOZONE_SWITCH_1_TCPROUTER_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_OUTPUT" "IsoZone-01" "tcp-router")
export ISOZONE_SWITCH_1_GOROUTER_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_OUTPUT" "IsoZone-01" "go-router")
export ISOZONE_SWITCH_1_TCPROUTER_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_OUTPUT" "IsoZone-01" "tcp-router")
export ISOZONE_SWITCH_1_GOROUTER_LBR_DETAILS=$(fn_get_component_pool_details "$NSX_GEN_OUTPUT" "IsoZone-01" "go-router")
export ISOZONE_SWITCH_1_TCPROUTER_LBR_DETAILS=$(fn_get_component_pool_details "$NSX_GEN_OUTPUT" "IsoZone-01" "tcp-router")

echo "Found ISOZONE-01 Virtual Switch           : $ISOZONE_SWITCH_1_VCENTER_NETWORK"
echo ""
echo "Found LBR    IP   for ISOZONE-01 GoRouter  : $ISOZONE_SWITCH_1_GOROUTER_LBR_IP"
echo "Found Static IPs  for ISOZONE-01 GoRouter  : $ISOZONE_SWITCH_1_GOROUTER_STATIC_IPS"
echo "Found LBR    IP   for ISOZONE-01 TcpRouter : $ISOZONE_SWITCH_1_TCPROUTER_LBR_IP"
echo "Found Static IPs  for ISOZONE-01 TcpRouter : $ISOZONE_SWITCH_1_TCPROUTER_STATIC_IPS"
echo "Found LBR Details for ISOZONE-01 GoRouter  : $ISOZONE_SWITCH_1_GOROUTER_LBR_DETAILS"
echo "Found LBR Details for ISOZONE-01 TcpRouter : $ISOZONE_SWITCH_1_TCPROUTER_LBR_DETAILS"
echo ""

export ISOZONE_SWITCH_2_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_OUTPUT" "IsoZone-02")
export ISOZONE_SWITCH_2_GOROUTER_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_OUTPUT" "IsoZone-02" "go-router")
export ISOZONE_SWITCH_2_TCPROUTER_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_OUTPUT" "IsoZone-02" "tcp-router")
export ISOZONE_SWITCH_2_GOROUTER_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_OUTPUT" "IsoZone-02" "go-router")
export ISOZONE_SWITCH_2_TCPROUTER_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_OUTPUT" "IsoZone-02" "tcp-router")
export ISOZONE_SWITCH_2_GOROUTER_LBR_DETAILS=$(fn_get_component_pool_details "$NSX_GEN_OUTPUT" "IsoZone-02" "go-router")
export ISOZONE_SWITCH_2_TCPROUTER_LBR_DETAILS=$(fn_get_component_pool_details "$NSX_GEN_OUTPUT" "IsoZone-02" "tcp-router")

echo "Found ISOZONE-02 Virtual Switch           : $ISOZONE_SWITCH_2_VCENTER_NETWORK"
echo ""
echo "Found LBR    IP   for ISOZONE-02 GoRouter  : $ISOZONE_SWITCH_2_GOROUTER_LBR_IP"
echo "Found Static IPs  for ISOZONE-02 GoRouter  : $ISOZONE_SWITCH_2_GOROUTER_STATIC_IPS"
echo "Found LBR    IP   for ISOZONE-02 TcpRouter : $ISOZONE_SWITCH_2_TCPROUTER_LBR_IP"
echo "Found Static IPs  for ISOZONE-02 TcpRouter : $ISOZONE_SWITCH_2_TCPROUTER_STATIC_IPS"
echo "Found LBR Details for ISOZONE-01 GoRouter  : $ISOZONE_SWITCH_2_GOROUTER_LBR_DETAILS"
echo "Found LBR Details for ISOZONE-01 TcpRouter : $ISOZONE_SWITCH_2_TCPROUTER_LBR_DETAILS"
echo ""

export ISOZONE_SWITCH_3_VCENTER_NETWORK=$(fn_get_pg "$NSX_GEN_OUTPUT" "IsoZone-03")
export ISOZONE_SWITCH_3_GOROUTER_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_OUTPUT" "IsoZone-03" "go-router")
export ISOZONE_SWITCH_3_TCPROUTER_STATIC_IPS=$(fn_get_component_static_ips "$NSX_GEN_OUTPUT" "IsoZone-03" "tcp-router")
export ISOZONE_SWITCH_3_GOROUTER_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_OUTPUT" "IsoZone-03" "go-router")
export ISOZONE_SWITCH_3_TCPROUTER_LBR_IP=$(fn_get_component_lbr_ip "$NSX_GEN_OUTPUT" "IsoZone-03" "tcp-router")
export ISOZONE_SWITCH_3_GOROUTER_LBR_DETAILS=$(fn_get_component_pool_details "$NSX_GEN_OUTPUT" "IsoZone-03" "go-router")
export ISOZONE_SWITCH_3_TCPROUTER_LBR_DETAILS=$(fn_get_component_pool_details "$NSX_GEN_OUTPUT" "IsoZone-03" "tcp-router")

echo "Found ISOZONE-03 Virtual Switch           : $ISOZONE_SWITCH_3_VCENTER_NETWORK"
echo ""
echo "Found LBR    IP   for ISOZONE-03 GoRouter  : $ISOZONE_SWITCH_3_GOROUTER_LBR_IP"
echo "Found Static IPs  for ISOZONE-03 GoRouter  : $ISOZONE_SWITCH_3_GOROUTER_STATIC_IPS"
echo "Found LBR    IP   for ISOZONE-03 TcpRouter : $ISOZONE_SWITCH_3_TCPROUTER_LBR_IP"
echo "Found Static IPs  for ISOZONE-03 TcpRouter : $ISOZONE_SWITCH_3_TCPROUTER_STATIC_IPS"
echo "Found LBR Details for ISOZONE-03 GoRouter  : $ISOZONE_SWITCH_3_GOROUTER_LBR_DETAILS"
echo "Found LBR Details for ISOZONE-03 TcpRouter : $ISOZONE_SWITCH_3_TCPROUTER_LBR_DETAILS"
echo ""

### All ERT Jobs
# "consul_server"
# "nats"
# "etcd_tls_server"
# "nfs_server"
# "mysql_proxy"
# "mysql"
# "backup-prepare"
# "ccdb"
# "diego_database"
# "uaadb"
# "uaa"
# "cloud_controller"
# "ha_proxy"
# "router"
# "mysql_monitor"
# "clock_global"
# "cloud_controller_worker"
# "diego_brain"
# "diego_cell"
# "loggregator_trafficcontroller"
# "syslog_adapter"
# "syslog_scheduler"
# "doppler"
# "tcp_router"
# "smoke-tests"
# "push-apps-manager"
# "notifications"
# "notifications-ui"
# "push-pivotal-account"
# "autoscaling"
# "autoscaling-register-broker"
# "nfsbrokerpush"
# "bootstrap"
# "mysql-rejoin-unsafe"
###
### Those that require LBR: mysql_proxy, tcp_router, router, diego_brain

### All MySQL Tile Jobs
# "mysql"
# "backup-prepare"
# "proxy"
# "monitoring"
# "cf-mysql-broker"
# "broker-registrar"
# "deregister-and-purge-instances"
# "rejoin-unsafe"
# "smoke-tests"
# "bootstrap"
###
### Those that require LBR: proxy

### All RabbitMQ Tile Jobs
# "rabbitmq-server"
# "rabbitmq-haproxy"
# "rabbitmq-broker"
# "broker-registrar"
# "broker-deregistrar"
###
### Those that require LBR: rabbitmq-haproxy

### All Isolation Segment Tile Jobs
# "isolated_router"
# "isolated_diego_cell"
# "isolated_tcp_router"
# "router".    # for Pre-1.11
# "tcp_router" # for Pre-1.11
###
### Those that require LBR: rabbitmq-haproxy


export ERT_TILE_JOBS_REQUIRING_LBR='mysql_proxy,tcp_router,router,diego_brain'
export MYSQL_TILE_JOBS_REQUIRING_LBR='proxy'
export RABBITMQ_TILE_JOBS_REQUIRING_LBR='rabbitmq-haproxy'
export ISO_TILE_JOBS_REQUIRING_LBR='tcp_router,router,isolated_tcp_router,isolated_router'

declare -A ERT_TILE_JOBS_LBR_MAP
ERT_TILE_JOBS_LBR_MAP=( ["mysql_proxy"]="$ERT_MYSQL_LBR_DETAILS" \
  ["tcp_router"]="$ERT_TCPROUTER_LBR_DETAILS" \
  ["diego_brain"]="$SSH_LBR_DETAILS" \
  ["router"]="$ERT_GOROUTER_LBR_DETAILS" )

declare -A MYSQL_TILE_JOBS_LBR_MAP
MYSQL_TILE_JOBS_LBR_MAP=( [proxy]="$MYSQL_TILE_LBR_DETAILS" )

declare -A RABBITMQ_TILE_JOBS_LBR_MAP
RABBITMQ_TILE_JOBS_LBR_MAP=( [rabbitmq-haproxy]="$RABBITMQ_TILE_LBR_DETAILS" )

declare -A ISO_TILE_1_JOBS_LBR_MAP
ISO_TILE_1_JOBS_LBR_MAP=( [tcp_router]="$ISOZONE_SWITCH_1_TCPOROUTER_LBR_DETAILS" \
 [router]="$ISOZONE_SWITCH_1_GOROUTER_LBR_DETAILS" \
 [isolated_tcp_router]="$ISOZONE_SWITCH_1_TCPOROUTER_LBR_DETAILS"  \
 [isolated_router]="$ISOZONE_SWITCH_1_GOROUTER_LBR_DETAILS" )

declare -A ISO_TILE_2_JOBS_LBR_MAP
ISO_TILE_2_JOBS_LBR_MAP=( [tcp_router]="$ISOZONE_SWITCH_2_TCPOROUTER_LBR_DETAILS" \
 [router]="$ISOZONE_SWITCH_2_GOROUTER_LBR_DETAILS" \
 [isolated_tcp_router]="$ISOZONE_SWITCH_2_TCPOROUTER_LBR_DETAILS"  \
 [isolated_router]="$ISOZONE_SWITCH_2_GOROUTER_LBR_DETAILS" )

declare -A ISO_TILE_3_JOBS_LBR_MAP
ISO_TILE_3_JOBS_LBR_MAP=( [tcp_router]="$ISOZONE_SWITCH_3_TCPOROUTER_LBR_DETAILS" \
 [router]="$ISOZONE_SWITCH_3_GOROUTER_LBR_DETAILS"
 [isolated_tcp_router]="$ISOZONE_SWITCH_3_TCPOROUTER_LBR_DETAILS"  \
 [isolated_router]="$ISOZONE_SWITCH_3_GOROUTER_LBR_DETAILS" )

declare -p ERT_TILE_JOBS_LBR_MAP > /tmp/jobs_lbr_map.out
declare -p MYSQL_TILE_JOBS_LBR_MAP >> /tmp/jobs_lbr_map.out
declare -p RABBITMQ_TILE_JOBS_LBR_MAP >> /tmp/jobs_lbr_map.out
declare -p ISO_TILE_1_JOBS_LBR_MAP >> /tmp/jobs_lbr_map.out
declare -p ISO_TILE_2_JOBS_LBR_MAP >> /tmp/jobs_lbr_map.out
declare -p ISO_TILE_3_JOBS_LBR_MAP >> /tmp/jobs_lbr_map.out
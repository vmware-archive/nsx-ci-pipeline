#!/bin/bash
set -e


pushd nsx-edge-gen  >/dev/null 2>&1

# Remove any existing config file template from the repo
if [[ -e nsx_cloud_config.yml ]]; then rm -rf nsx_cloud_config.yml; fi


# Init new config file template
./nsx-gen/bin/nsxgen -i $NSX_EDGE_GEN_NAME init
ARGS=" "

if [ "$ISOZONE_SWITCH_NAME_1" != "" ]; then
  ARGS="$ARGS 
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

if [ "$ISOZONE_SWITCH_NAME_2" != "" ]; then
  ARGS="$ARGS 
  -isozone_switch_name_2 $ISOZONE_SWITCH_NAME_2
  -isozone_switch_cidr_2 $ISOZONE_SWITCH_CIDR_2
  -esg_go_router_isozone_2_uplink_ip_1 $ESG_GO_ROUTER_ISOZONE_2_UPLINK_IP_1
  -esg_go_router_isozone_2_switch_1 $ISOZONE_SWITCH_NAME_2
  -esg_go_router_isozone_2_inst_1 $ESG_GO_ROUTER_ISOZONE_2_INST_1
  -esg_tcp_router_isozone_2_uplink_ip_1 $ESG_TCP_ROUTER_ISOZONE_2_UPLINK_IP_1 
  -esg_tcp_router_isozone_2_switch_1 $ISOZONE_SWITCH_NAME_2
  -esg_tcp_router_isozone_2_inst_1 $ESG_TCP_ROUTER_ISOZONE_2_INST_1
  "
fi

if [ "$ISOZONE_SWITCH_NAME_3" != "" ]; then
  ARGS="$ARGS 
  -isozone_switch_name_3 $ISOZONE_SWITCH_NAME_3
  -isozone_switch_cidr_3 $ISOZONE_SWITCH_CIDR_3
  -esg_go_router_isozone_3_uplink_ip_1 $ESG_GO_ROUTER_ISOZONE_3_UPLINK_IP_1
  -esg_go_router_isozone_3_switch_1 $ISOZONE_SWITCH_NAME_3
  -esg_go_router_isozone_3_inst_1 $ESG_GO_ROUTER_ISOZONE_3_INST_1
  -esg_tcp_router_isozone_3_uplink_ip_1 $ESG_TCP_ROUTER_ISOZONE_3_UPLINK_IP_1 
  -esg_tcp_router_isozone_3_switch_1 $ISOZONE_SWITCH_NAME_3
  -esg_tcp_router_isozone_3_inst_1 $ESG_TCP_ROUTER_ISOZONE_3_INST_1
  "
fi

./nsx-gen/bin/nsxgen \
-c $NSX_EDGE_GEN_NAME \
-esg_name_1 $NSX_EDGE_GEN_NAME \
-esg_size_1 $ESG_SIZE  \
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
-esg_go_router_inst_1 $ESG_GO_ROUTER_INSTANCES_1 \
-esg_diego_brain_inst_1 $ESG_DIEGO_BRAIN_INSTANCES_1 \
-esg_tcp_router_inst_1 $ESG_TCP_ROUTER_INSTANCES_1 \
-esg_mysql_ert_inst_1 $ESG_MYSQL_ERT_PROXY_INSTANCES_1 \
-esg_mysql_tile_inst_1 $ESG_MYSQL_TILE_PROXY_INSTANCES_1  \
-esg_rabbitmq_tile_inst_1 $ESG_RABBITMQ_TILE_PROXY_INSTANCES_1 \
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
build 


popd  >/dev/null 2>&1

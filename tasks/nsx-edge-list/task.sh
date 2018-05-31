#!/bin/bash
set -e

export ROOT_DIR=`pwd`
export SCRIPT_DIR=$(dirname $0)
#echo pwd is $PWD and `pwd`
#echo SCRIPT_DIR is $SCRIPT_DIR
export NSX_GEN_OUTPUT_DIR="${ROOT_DIR}/nsx-gen-output"
mkdir -p ${NSX_GEN_OUTPUT_DIR}

export NSX_GEN_OUTPUT=${NSX_GEN_OUTPUT_DIR}/nsx-gen-out.log
export NSX_GEN_UTIL="${SCRIPT_DIR}/nsx_parse_util.sh"

pushd nsx-edge-gen  >/dev/null 2>&1


# Remove any existing config file template from the repo
if [[ -e nsx_cloud_config.yml ]]; then rm -rf nsx_cloud_config.yml; fi

# Init new config file template
./nsx-gen/bin/nsxgen -i $NSX_EDGE_GEN_NAME init
ARGS=" "

if [ "$ISOZONE_SWITCH_NAME_1" != "" ]; then
  ARGS="$ARGS \
  -isozone_switch_name_1 $ISOZONE_SWITCH_NAME_1 \
  -isozone_switch_cidr_1 $ISOZONE_SWITCH_CIDR_1 \
  -esg_go_router_isozone_1_uplink_ip_1 $ESG_GO_ROUTER_ISOZONE_1_UPLINK_IP_1 \
  -esg_go_router_isozone_1_switch_1 $ISOZONE_SWITCH_NAME_1 \
  -esg_go_router_isozone_1_inst_1 $ESG_GO_ROUTER_ISOZONE_1_INST_1 \
  -esg_tcp_router_isozone_1_uplink_ip_1 $ESG_TCP_ROUTER_ISOZONE_1_UPLINK_IP_1 \
  -esg_tcp_router_isozone_1_switch_1 $ISOZONE_SWITCH_NAME_1 \
  -esg_tcp_router_isozone_1_inst_1 $ESG_TCP_ROUTER_ISOZONE_1_INST_1 \
  -esg_go_router_isozone_1_ssl_term_1 $ESG_GO_ROUTER_ISOZONE_1_SSL_TERM_1 \
   "

  if [ "$ESG_ISO_CERTS_CONFIG_DOMAINS_1_1" != "" ]; then
    ARGS="$ARGS \
    -esg_iso_certs_1_1 $ESG_ISO_CERTS_NAME_1_1 \
    -esg_iso_certs_config_switch_1_1 $ESG_ISO_CERTS_SWITCH_1_1 \
    -esg_iso_certs_config_ou_1_1 $ESG_ISO_CERTS_CONFIG_OU_1_1 \
    -esg_iso_certs_config_cc_1_1 $ESG_ISO_CERTS_CONFIG_COUNTRY_1_1 \
    -esg_iso_certs_config_domains_1_1 $ESG_ISO_CERTS_CONFIG_DOMAINS_1_1 \
     "
  fi
fi

if [ "$ISOZONE_SWITCH_NAME_2" != "" ]; then
  ARGS="$ARGS \
  -isozone_switch_name_2 $ISOZONE_SWITCH_NAME_2 \
  -isozone_switch_cidr_2 $ISOZONE_SWITCH_CIDR_2 \
  -esg_go_router_isozone_2_uplink_ip_1 $ESG_GO_ROUTER_ISOZONE_2_UPLINK_IP_1 \
  -esg_go_router_isozone_2_switch_1 $ISOZONE_SWITCH_NAME_2 \
  -esg_go_router_isozone_2_inst_1 $ESG_GO_ROUTER_ISOZONE_2_INST_1 \
  -esg_tcp_router_isozone_2_uplink_ip_1 $ESG_TCP_ROUTER_ISOZONE_2_UPLINK_IP_1 \
  -esg_tcp_router_isozone_2_switch_1 $ISOZONE_SWITCH_NAME_2 \
  -esg_tcp_router_isozone_2_inst_1 $ESG_TCP_ROUTER_ISOZONE_2_INST_1 \
  -esg_go_router_isozone_2_ssl_term_1 $ESG_GO_ROUTER_ISOZONE_2_SSL_TERM_1 \
  "

  if [ "$ESG_ISO_CERTS_CONFIG_DOMAINS_2_1" != "" ]; then
    ARGS="$ARGS \
    -esg_iso_certs_2_1 $ESG_ISO_CERTS_NAME_2_1 \
    -esg_iso_certs_config_switch_2_1 $ESG_ISO_CERTS_SWITCH_2_1 \
    -esg_iso_certs_config_ou_2_1 $ESG_ISO_CERTS_CONFIG_OU_2_1 \
    -esg_iso_certs_config_cc_2_1 $ESG_ISO_CERTS_CONFIG_COUNTRY_2_1 \
    -esg_iso_certs_config_domains_2_1 $ESG_ISO_CERTS_CONFIG_DOMAINS_2_1 \
     "
  fi
fi

if [ "$ISOZONE_SWITCH_NAME_3" != "" ]; then
  ARGS="$ARGS \
  -isozone_switch_name_3 $ISOZONE_SWITCH_NAME_3 \
  -isozone_switch_cidr_3 $ISOZONE_SWITCH_CIDR_3 \
  -esg_go_router_isozone_3_uplink_ip_1 $ESG_GO_ROUTER_ISOZONE_3_UPLINK_IP_1 \
  -esg_go_router_isozone_3_switch_1 $ISOZONE_SWITCH_NAME_3 \
  -esg_go_router_isozone_3_inst_1 $ESG_GO_ROUTER_ISOZONE_3_INST_1 \
  -esg_tcp_router_isozone_3_uplink_ip_1 $ESG_TCP_ROUTER_ISOZONE_3_UPLINK_IP_1 \
  -esg_tcp_router_isozone_3_switch_1 $ISOZONE_SWITCH_NAME_3 \
  -esg_tcp_router_isozone_3_inst_1 $ESG_TCP_ROUTER_ISOZONE_3_INST_1 \
  -esg_go_router_isozone_3_ssl_term_1 $ESG_GO_ROUTER_ISOZONE_3_SSL_TERM_1 \
  "

  if [ "$ESG_ISO_CERTS_CONFIG_DOMAINS_3_1" != "" ]; then
    ARGS="$ARGS \
    -esg_iso_certs_3_1 $ESG_ISO_CERTS_NAME_3_1 \
    -esg_iso_certs_config_switch_3_1 $ESG_ISO_CERTS_SWITCH_3_1 \
    -esg_iso_certs_config_ou_3_1 $ESG_ISO_CERTS_CONFIG_OU_3_1 \
    -esg_iso_certs_config_cc_3_1 $ESG_ISO_CERTS_CONFIG_COUNTRY_3_1 \
    -esg_iso_certs_config_domains_3_1 $ESG_ISO_CERTS_CONFIG_DOMAINS_3_1 \
     "
  fi
fi


if [ "$(echo $ERT_SSL_CERT | grep '.')" != "" ]; then
  ARGS="$ARGS \
  -esg_ert_certs_cert_1 \"$ERT_SSL_CERT\" \
  -esg_ert_certs_key_1 \"$ERT_SSL_PRIVATE_KEY\" \
  "
fi

if [ "$(echo $ISOZONE_SSL_CERT_1 | grep '.')" != "" ]; then
  ARGS="$ARGS \
  -esg_iso_certs_cert_1_1 \"$ISOZONE_SSL_CERT_1\" \
  -esg_iso_certs_key_1_1 \"$ISOZONE_SSL_PRIVATE_KEY_1\" \
  "
fi

if [ "$(echo $ISOZONE_SSL_CERT_2 | grep '.')" != "" ]; then
  ARGS="$ARGS \
  -esg_iso_certs_cert_2_1 \"$ISOZONE_SSL_CERT_2\" \
  -esg_iso_certs_key_2_1 \"$ISOZONE_SSL_PRIVATE_KEY_2\" \
  "
fi

if [ "$(echo $ISOZONE_SSL_CERT_3 | grep '.')" != "" ]; then
  #echo $ISOZONE_SSL_CERT_3 | tr '\n' '#'| sed -e 's/#/\\r\\n/g' > /tmp/iso3_sanitised_ssl_cert
  #echo $ISOZONE_SSL_PRIVATE_KEY_3 | tr '\n' '#'| sed -e 's/#/\\r\\n/g'  > /tmp/iso3_sanitised_ssl_private_key

  ARGS="$ARGS \
  -esg_iso_certs_cert_3_1 \"$ISOZONE_SSL_CERT_3\" \
  -esg_iso_certs_key_3_1 \"$ISOZONE_SSL_PRIVATE_KEY_3\" \
  "
fi

cat >  /tmp/nsx-run.sh <<-EOF
#!/bin/bash
pushd "${ROOT_DIR}/nsx-edge-gen"
./nsx-gen/bin/nsxgen \
-c "$NSX_EDGE_GEN_NAME" \
-esg_name_1 "$NSX_EDGE_GEN_NAME" \
-esg_ospf_password_1 "$ESG_OSPF_PASSWORD_1"  \
-esg_cli_user_1 "$ESG_CLI_USERNAME_1"   \
-esg_cli_pass_1 "$ESG_CLI_PASSWORD_1"   \
-esg_ert_certs_1 "$ESG_ERT_CERTS_NAME_1"   \
-esg_ert_certs_config_sysd_1 "$ESG_ERT_CERTS_CONFIG_SYSTEMDOMAIN_1"   \
-esg_ert_certs_config_appd_1 "$ESG_ERT_CERTS_CONFIG_APPDOMAIN_1"   \
-esg_go_router_ssl_term_1 "$ESG_GO_ROUTER_SSL_TERM_1" \
-esg_opsmgr_uplink_ip_1 $ESG_OPSMGR_UPLINK_IP_1   \
-esg_opsdir_uplink_ip_1 "$ESG_OPSDIR_UPLINK_IP_1" \
-esg_go_router_uplink_ip_1 "$ESG_GO_ROUTER_UPLINK_IP_1" \
-esg_go_router_nossl_uplink_ip_1 "$ESG_GO_ROUTER_NOSSL_UPLINK_IP_1" \
-esg_diego_brain_uplink_ip_1 $ESG_DIEGO_BRAIN_UPLINK_IP_1   \
-esg_tcp_router_uplink_ip_1 $ESG_TCP_ROUTER_UPLINK_IP_1   \
-esg_go_router_inst_1 $ESG_GO_ROUTER_INSTANCES_1 \
-esg_diego_brain_inst_1 $ESG_DIEGO_BRAIN_INSTANCES_1 \
-esg_tcp_router_inst_1 $ESG_TCP_ROUTER_INSTANCES_1 \
-esg_mysql_ert_inst_1 $ESG_MYSQL_ERT_PROXY_INSTANCES_1 \
-esg_mysql_tile_inst_1 $ESG_MYSQL_TILE_PROXY_INSTANCES_1  \
-esg_rabbitmq_tile_inst_1 $ESG_RABBITMQ_TILE_PROXY_INSTANCES_1 \
-esg_gateway_1 $ESG_GATEWAY_1 \
-vcenter_addr "$VCENTER_HOST"   \
-vcenter_user "$VCENTER_USR"   \
-vcenter_pass "$VCENTER_PWD"   \
-vcenter_dc "$VCENTER_DATA_CENTER"   \
-vcenter_ds "$NSX_EDGE_GEN_EDGE_DATASTORE"   \
-vcenter_cluster "$NSX_EDGE_GEN_EDGE_CLUSTER"  \
-nsxmanager_addr "$NSX_EDGE_GEN_NSX_MANAGER_ADDRESS"  \
-nsxmanager_user "$NSX_EDGE_GEN_NSX_MANAGER_ADMIN_USER"   \
-nsxmanager_pass "$NSX_EDGE_GEN_NSX_MANAGER_ADMIN_PASSWD"   \
-nsxmanager_tz "$NSX_EDGE_GEN_NSX_MANAGER_TRANSPORT_ZONE"   \
-nsxmanager_tz_clusters "$NSX_EDGE_GEN_NSX_MANAGER_TRANSPORT_ZONE_CLUSTERS" \
-nsxmanager_dportgroup "$NSX_EDGE_GEN_NSX_MANAGER_DISTRIBUTED_PORTGROUP" \
-nsxmanager_uplink_ip $ESG_DEFAULT_UPLINK_IP_1  \
-nsxmanager_uplink_port "$ESG_DEFAULT_UPLINK_PG_1" \
-nsxmanager_en_dlr "$NSX_EDGE_GEN_ENABLE_DLR" \
-nsxmanager_bosh_nsx_enabled "$NSX_EDGE_GEN_BOSH_NSX_ENABLED" \
$ARGS \
list 
EOF
chmod +x /tmp/nsx-run.sh
/tmp/nsx-run.sh | tee $NSX_GEN_OUTPUT 2>&1

popd  >/dev/null 2>&1

cp ${NSX_GEN_UTIL} ${NSX_GEN_OUTPUT_DIR}/


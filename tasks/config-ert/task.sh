#!/bin/bash

set -e

chmod +x om-cli/om-linux

export ROOT_DIR=`pwd`
export SCRIPT_DIR=$(dirname $0)
export NSX_GEN_OUTPUT_DIR=${ROOT_DIR}/nsx-gen-output
export NSX_GEN_OUTPUT=${NSX_GEN_OUTPUT_DIR}/nsx-gen-out.log
export NSX_GEN_UTIL=${NSX_GEN_OUTPUT_DIR}/nsx_parse_util.sh

if [ -e "${NSX_GEN_OUTPUT}" ]; then
  #echo "Saved nsx gen output:"
  #cat ${NSX_GEN_OUTPUT}
  source ${NSX_GEN_UTIL} ${NSX_GEN_OUTPUT}
else
  echo "Unable to retreive nsx gen output generated from previous nsx-gen-list task!!"
  exit 1
fi

# No need to associate a static ip for MySQL Proxy for ERT
# export MYSQL_ERT_PROXY_IP=$(echo ${DEPLOYMENT_NW_CIDR} | \
#                            sed -e 's/\/.*//g' | \
#                            awk -F '.' '{print $1"."$2"."$3".250"}' ) 
# use $ERT_MYSQL_LBR_IP for proxy - retreived from nsx-gen-list

CF_RELEASE=`./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k available-products | grep cf`

PRODUCT_NAME=`echo $CF_RELEASE | cut -d"|" -f2 | tr -d " "`
PRODUCT_VERSION=`echo $CF_RELEASE | cut -d"|" -f3 | tr -d " "`

./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k stage-product -p $PRODUCT_NAME -v $PRODUCT_VERSION

function fn_get_azs {
     local azs_csv=$1
     echo $azs_csv | awk -F "," -v braceopen='{' -v braceclose='}' -v name='"name":' -v quote='"' -v OFS='"},{"name":"' '$1=$1 {print braceopen name quote $0 quote braceclose}'
}

OTHER_AVAILABILITY_ZONES=$(fn_get_azs $AZS_ERT)

CF_NETWORK=$(cat <<-EOF
{
  "singleton_availability_zone": {
    "name": "$AZ_ERT_SINGLETON"
  },
  "other_availability_zones": [
    $OTHER_AVAILABILITY_ZONES
  ],
  "network": {
    "name": "$NETWORK_NAME"
  }
}
EOF
)

if [[ -z "$SSL_CERT" ]]; then
DOMAINS=$(cat <<-EOF
  {"domains": ["*.$SYSTEM_DOMAIN", "*.$APPS_DOMAIN", "*.login.$SYSTEM_DOMAIN", "*.uaa.$SYSTEM_DOMAIN"] }
EOF
)

  CERTIFICATES=`./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl -p "/api/v0/certificates/generate" -x POST -d "$DOMAINS"`

  export SSL_CERT=`echo $CERTIFICATES | jq '.certificate'`
  export SSL_PRIVATE_KEY=`echo $CERTIFICATES | jq '.key'`

  echo "SSL_CERT is" $SSL_CERT
  echo "SSL_PRIVATE_KEY is" $SSL_PRIVATE_KEY
else
  echo "Using certs passed in YML"
fi

CF_PROPERTIES=$(cat <<-EOF
{
  ".properties.logger_endpoint_port": {
    "value": "$LOGGREGATOR_ENDPOINT_PORT"
  },
  ".properties.syslog_host": {
    "value": "$SYSLOG_HOST"
  },
  ".properties.syslog_port": {
    "value": "$SYSLOG_PORT"
  },
  ".properties.syslog_protocol": {
    "value": "$SYSLOG_PROTOCOL"
  },
  ".properties.networking_point_of_entry": {
    "value": "$NETWORK_POINT_OF_ENTRY"
  },
EOF
)

if [[ $NETWORK_POINT_OF_ENTRY = "external_ssl" ]]; then
CF_PROPERTIES=$(cat <<-EOF
$CF_PROPERTIES
  ".properties.networking_point_of_entry.external_ssl.ssl_rsa_certificate": {
    "value": {
      "cert_pem": $SSL_CERT,
      "private_key_pem": $SSL_PRIVATE_KEY
    }
  },
EOF
)
fi

CF_PROPERTIES=$(cat <<-EOF
$CF_PROPERTIES
  ".properties.tcp_routing": {
    "value": "$TCP_ROUTING"
  },
  ".properties.tcp_routing.enable.reservable_ports": {
    "value": "$TCP_ROUTING_PORTS"
  },
  ".properties.route_services": {
    "value": "$ROUTE_SERVICES"
  },
  ".properties.route_services.enable.ignore_ssl_cert_verification": {
    "value": $IGNORE_SSL_CERT
  },
  ".properties.security_acknowledgement": {
    "value": "X"
  },
  ".properties.smtp_from": {
    "value": "$SMTP_FROM"
  },
  ".properties.smtp_address": {
    "value": "$SMTP_ADDRESS"
  },
  ".properties.smtp_port": {
    "value": "$SMTP_PORT"
  },
  ".properties.smtp_credentials": {
    "value": {
      "identity": "$SMTP_USER",
      "password": "$SMTP_PWD"
    }
  },
  ".properties.smtp_enable_starttls_auto": {
    "value": true
  },
  ".properties.smtp_auth_mechanism": {
    "value": "$SMTP_AUTH_MECHANISM"
  },
  ".properties.system_blobstore": {
    "value": "internal"
  },
  ".properties.mysql_backups": {
    "value": "disable"
  },
  ".mysql_proxy.static_ips": {
    "value": "$ERT_MYSQL_STATIC_IPS"
  },
  ".mysql_proxy.service_hostname": {
    "value": "$ERT_MYSQL_LBR_IP"
  },
  ".properties.uaa": {
    "value": "$UAA_METHOD"
  },
EOF
)

if [[ $UAA_METHOD = "ldap" ]]; then
CF_PROPERTIES=$(cat <<-EOF
$CF_PROPERTIES
  ".properties.uaa.ldap.url": {
    "value": "$LDAP_URL"
  },
  ".properties.uaa.ldap.credentials": {
    "value": {
      "identity": "$LDAP_USER",
      "password": "$LDAP_PWD"
    }
  },
  ".properties.uaa.ldap.search_base": {
    "value": "$SEARCH_BASE"
  },
  ".properties.uaa.ldap.search_filter": {
    "value": "$SEARCH_FILTER"
  },
  ".properties.uaa.ldap.group_search_base": {
    "value": "$GROUP_SEARCH_BASE"
  },
  ".properties.uaa.ldap.group_search_filter": {
    "value": "$GROUP_SEARCH_FILTER"
  },
  ".properties.uaa.ldap.mail_attribute_name": {
    "value": "$MAIL_ATTR_NAME"
  },
  ".properties.uaa.ldap.first_name_attribute": {
    "value": "$FIRST_NAME_ATTR"
  },
  ".properties.uaa.ldap.last_name_attribute": {
    "value": "$LAST_NAME_ATTR"
  },
EOF
)
fi

CF_PROPERTIES=$(cat <<-EOF
$CF_PROPERTIES
  ".cloud_controller.system_domain": {
    "value": "$SYSTEM_DOMAIN"
  },
  ".cloud_controller.apps_domain": {
    "value": "$APPS_DOMAIN"
  },
  ".cloud_controller.default_quota_memory_limit_mb": {
    "value": 10240
  },
  ".cloud_controller.default_quota_max_number_services": {
    "value": 1000
  },
  ".cloud_controller.allow_app_ssh_access": {
    "value": true
  },
  ".cloud_controller.security_event_logging_enabled": {
    "value": true
  },
  ".ha_proxy.static_ips": {
    "value": "$HA_PROXY_IPS"
  },
  ".ha_proxy.skip_cert_verify": {
    "value": $SKIP_CERT_VERIFY
  },
  ".router.static_ips": {
    "value": "$ERT_GOROUTER_STATIC_IPS"
  },
  ".router.disable_insecure_cookies": {
    "value": false
  },
  ".router.request_timeout_in_seconds": {
    "value": 900
  },
  ".mysql_monitor.recipient_email": {
    "value": "$MYSQL_MONITOR_EMAIL"
  },
  ".diego_cell.garden_network_pool": {
    "value": "10.254.0.0/22"
  },
  ".diego_cell.garden_network_mtu": {
    "value": 1454
  },
  ".doppler.message_drain_buffer_size": {
    "value": 10000
  },
  ".tcp_router.static_ips": {
    "value": "$ERT_TCPROUTER_STATIC_IPS"
  },
  ".push-apps-manager.company_name": {
    "value": "NSXIntPipeline"
  },
  ".diego_brain.static_ips": {
    "value": "$SSH_STATIC_IPS"
  }
}
EOF
)

CF_RESOURCES=$(cat <<-EOF
{
  "consul_server": {
    "instance_type": {"id": "automatic"},
    "instances" : $CONSUL_SERVER_INSTANCES
  },
  "nats": {
    "instance_type": {"id": "automatic"},
    "instances" : $NATS_INSTANCES
  },
  "etcd_tls_server": {
    "instance_type": {"id": "automatic"},
    "instances" : $ETCD_TLS_SERVER_INSTANCES
  },
  "nfs_server": {
    "instance_type": {"id": "automatic"},
    "instances" : $NFS_SERVER_INSTANCES
  },
  "mysql_proxy": {
    "instance_type": {"id": "automatic"},
    "instances" : $MYSQL_PROXY_INSTANCES
  },
  "mysql": {
    "instance_type": {"id": "automatic"},
    "instances" : $MYSQL_INSTANCES
  },
  "backup-prepare": {
    "instance_type": {"id": "automatic"},
    "instances" : $BACKUP_PREPARE_INSTANCES
  },
  "ccdb": {
    "instance_type": {"id": "automatic"},
    "instances" : $CCDB_INSTANCES
  },
  "uaadb": {
    "instance_type": {"id": "automatic"},
    "instances" : $UAADB_INSTANCES
  },
  "uaa": {
    "instance_type": {"id": "automatic"},
    "instances" : $UAA_INSTANCES
  },
  "cloud_controller": {
    "instance_type": {"id": "automatic"},
    "instances" : $CLOUD_CONTROLLER_INSTANCES
  },
  "ha_proxy": {
    "instance_type": {"id": "automatic"},
    "instances" : $HA_PROXY_INSTANCES
  },
  "router": {
    "instance_type": {"id": "automatic"},
    "instances" : $ROUTER_INSTANCES
  },
  "mysql_monitor": {
    "instance_type": {"id": "automatic"},
    "instances" : $MYSQL_MONITOR_INSTANCES
  },
  "clock_global": {
    "instance_type": {"id": "automatic"},
    "instances" : $CLOCK_GLOBAL_INSTANCES
  },
  "cloud_controller_worker": {
    "instance_type": {"id": "automatic"},
    "instances" : $CLOUD_CONTROLLER_WORKER_INSTANCES
  },
  "diego_database": {
    "instance_type": {"id": "automatic"},
    "instances" : $DIEGO_DATABASE_INSTANCES
  },
  "diego_brain": {
    "instance_type": {"id": "automatic"},
    "instances" : $DIEGO_BRAIN_INSTANCES
  },
  "diego_cell": {
    "instance_type": {"id": "automatic"},
    "instances" : $DIEGO_CELL_INSTANCES
  },
  "doppler": {
    "instance_type": {"id": "automatic"},
    "instances" : $DOPPLER_INSTANCES
  },
  "loggregator_trafficcontroller": {
    "instance_type": {"id": "automatic"},
    "instances" : $LOGGREGATOR_TC_INSTANCES
  },
  "tcp_router": {
    "instance_type": {"id": "automatic"},
    "instances" : $TCP_ROUTER_INSTANCES
  }
}
EOF
)

./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k configure-product -n cf -p "$CF_PROPERTIES" -pn "$CF_NETWORK" -pr "$CF_RESOURCES"

# Set Errands to on Demand
echo "applying errand configuration"
sleep 6
ERT_ERRANDS=$(cat <<-EOF
{"errands":[
  {"name":"smoke-tests","post_deploy":"when-changed"},
  {"name":"push-apps-manager","post_deploy":"when-changed"},
  {"name":"notifications","post_deploy":"when-changed"},
  {"name":"notifications-ui","post_deploy":"when-changed"},
  {"name":"push-pivotal-account","post_deploy":"when-changed"},
  {"name":"autoscaling","post_deploy":"when-changed"},
  {"name":"autoscaling-register-broker","post_deploy":"when-changed"},
  {"name":"nfsbrokerpush","post_deploy":"when-changed"}
]}
EOF
)

CF_GUID=$(./om-cli/om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD curl -p "/api/v0/staged/products" -x GET | jq '.[] | select(.installation_name | contains("cf-")) | .guid' | tr -d '"')
./om-cli/om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD curl -p "/api/v0/staged/products/$CF_GUID/errands" -x PUT -d "$ERT_ERRANDS"

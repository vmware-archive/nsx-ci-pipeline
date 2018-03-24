#!/bin/bash



export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-ci-pipeline/functions/check_versions.sh


export SCRIPT_DIR=$(dirname $0)
export NSX_GEN_OUTPUT_DIR=${ROOT_DIR}/nsx-gen-output
export NSX_GEN_OUTPUT=${NSX_GEN_OUTPUT_DIR}/nsx-gen-out.log
export NSX_GEN_UTIL=${NSX_GEN_OUTPUT_DIR}/nsx_parse_util.sh

if [ -e "${NSX_GEN_OUTPUT}" ]; then
  #echo "Saved nsx gen output:"
  #cat ${NSX_GEN_OUTPUT}
  source ${NSX_GEN_UTIL} ${NSX_GEN_OUTPUT}

  # Read back associate array of jobs to lbr details
  # created by hte NSX_GEN_UTIL script
  source /tmp/jobs_lbr_map.out

  IS_NSX_ENABLED=$(om -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k \
               curl -p "/api/v0/deployed/director/manifest" 2>/dev/null | jq '.cloud_provider.properties.vcenter.nsx' || true )


  # if nsx is enabled
  if [ "$IS_NSX_ENABLED" != "null" -a "$IS_NSX_ENABLED" != "" ]; then
    IS_NSX_ENABLED=true
  fi

else
  echo "Unable to retreive nsx gen output generated from previous nsx-gen-list task!!"
  exit 1
fi



# No need to associate a static ip for MySQL Proxy for ERT
# export MYSQL_ERT_PROXY_IP=$(echo ${DEPLOYMENT_NW_CIDR} | \
#                            sed -e 's/\/.*//g' | \
#                            awk -F '.' '{print $1"."$2"."$3".250"}' ) 
# use $ERT_MYSQL_LBR_IP for proxy - retreived from nsx-gen-list

check_bosh_version
check_available_product_version "cf"

om \
    -t https://$OPS_MGR_HOST \
    -u $OPS_MGR_USR \
    -p $OPS_MGR_PWD  \
    -k stage-product \
    -p $PRODUCT_NAME \
    -v $PRODUCT_VERSION
  
check_staged_product_guid "cf-"

# when-changed option for errands is only applicable from Ops Mgr 1.10+
export IS_ERRAND_WHEN_CHANGED_ENABLED=false

if [ $BOSH_MAJOR_VERSION -le 1 ]; then
  if [ $BOSH_MINOR_VERSION -ge 10 ]; then
    export IS_ERRAND_WHEN_CHANGED_ENABLED=true
  fi
else
  export IS_ERRAND_WHEN_CHANGED_ENABLED=true
fi

# No C2C support in PCF 1.9, 1.10 and older versions
# only from 1.11+
export SUPPORTS_C2C=false
if [ $PRODUCT_MAJOR_VERSION -le 1 ]; then
  if [ $PRODUCT_MINOR_VERSION -ge 11 ]; then
    export SUPPORTS_C2C=true   
  fi
else
  export SUPPORTS_C2C=true
fi

function fn_get_azs {
     local azs_csv=$1
     echo $azs_csv | awk -F "," -v braceopen='{' -v braceclose='}' -v name='"name":' -v quote='"' -v OFS='"},{"name":"' '$1=$1 {print braceopen name quote $0 quote braceclose}'
}

OTHER_AVAILABILITY_ZONES=$(fn_get_azs $AZS_ERT)


# if [[ -z "$SSL_CERT" ]]; then
# DOMAINS=$(cat <<-EOF
#   {"domains": ["*.$SYSTEM_DOMAIN", "*.$APPS_DOMAIN", "*.login.$SYSTEM_DOMAIN", "*.uaa.$SYSTEM_DOMAIN"] }
# EOF
# )

#   CERTIFICATES=`om -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl -p "/api/v0/certificates/generate" -x POST -d "$DOMAINS"`

#   export SSL_CERT=`echo $CERTIFICATES | jq '.certificate'`
#   export SSL_PRIVATE_KEY=`echo $CERTIFICATES | jq '.key'`
#   # echo "SSL_CERT is" $SSL_CERT
#   # echo "SSL_PRIVATE_KEY is" $SSL_PRIVATE_KEY
# else
#   echo "Using certs passed in YML"
# fi


# saml_cert_domains=$(cat <<-EOF
#   {"domains": ["*.$SYSTEM_DOMAIN", "*.login.$SYSTEM_DOMAIN", "*.uaa.$SYSTEM_DOMAIN"] }
# EOF
# )

# saml_cert_response=`om -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl -p "$OPS_MGR_GENERATE_SSL_ENDPOINT" -x POST -d "$saml_cert_domains"`

# SAML_SSL_CERT=$(echo $saml_cert_response | jq --raw-output '.certificate')
# SAML_SSL_PRIVATE_KEY=$(echo $saml_cert_response | jq --raw-output '.key')


set -eu

source $ROOT_DIR/nsx-ci-pipeline/functions/generate_cert.sh

if [[ -z "$SSL_CERT" ]]; then
  domains=(
    "*.${SYSTEM_DOMAIN}"
    "*.${APPS_DOMAIN}"
    "*.login.${SYSTEM_DOMAIN}"
    "*.uaa.${SYSTEM_DOMAIN}"
  )

  certificates=$(generate_cert "${domains[*]}")
  SSL_CERT=`echo $certificates | jq --raw-output '.certificate'`
  SSL_PRIVATE_KEY=`echo $certificates | jq --raw-output '.key'`
fi


if [[ -z "$SAML_SSL_CERT" ]]; then
  saml_cert_domains=(
    "*.${SYSTEM_DOMAIN}"
    "*.login.${SYSTEM_DOMAIN}"
    "*.uaa.${SYSTEM_DOMAIN}"
  )

  saml_certificates=$(generate_cert "${saml_cert_domains[*]}")
  SAML_SSL_CERT=$(echo $saml_certificates | jq --raw-output '.certificate')
  SAML_SSL_PRIVATE_KEY=$(echo $saml_certificates | jq --raw-output '.key')
fi

# SABHA 
# Change in ERT 2.0 
# from: ".push-apps-manager.company_name"
# to: ".properties.push_apps_manager_company_name"

# Generate CredHub passwd
if [ "$CREDHUB_PASSWORD" == "" ]; then
  CREDHUB_PASSWORD=$(echo $OPSMAN_PASSWORD{,,,,} | sed -e 's/ //g' | cut -c1-25)
fi

has_blobstore_internal_access_subnet=$(echo $STAGED_PRODUCT_PROPERTIES | jq . | grep ".nfs_server\.blobstore_internal_access_rules" | wc -l || true)


cf_properties=$(
  jq -n \
    --arg nsx_enabled "$IS_NSX_ENABLED" \
    --arg tcp_routing "$TCP_ROUTING" \
    --arg tcp_routing_ports "$TCP_ROUTING_PORTS" \
    --arg loggregator_endpoint_port "$LOGGREGATOR_ENDPOINT_PORT" \
    --arg route_services "$ROUTE_SERVICES" \
    --arg ignore_ssl_cert "$IGNORE_SSL_CERT" \
    --arg security_acknowledgement "$SECURITY_ACKNOWLEDGEMENT" \
    --arg system_domain "$SYSTEM_DOMAIN" \
    --arg apps_domain "$APPS_DOMAIN" \
    --arg default_quota_memory_limit_in_mb "$DEFAULT_QUOTA_MEMORY_LIMIT_IN_MB" \
    --arg default_quota_max_services_count "$DEFAULT_QUOTA_MAX_SERVICES_COUNT" \
    --arg allow_app_ssh_access "$ALLOW_APP_SSH_ACCESS" \
    --arg ha_proxy_ips "$HA_PROXY_IPS" \
    --arg skip_cert_verify "$SKIP_CERT_VERIFY" \
    --arg ert_gorouter_static_ips "$ERT_GOROUTER_STATIC_IPS" \
    --arg disable_insecure_cookies "$DISABLE_INSECURE_COOKIES" \
    --arg router_request_timeout_seconds "$ROUTER_REQUEST_TIMEOUT_IN_SEC" \
    --arg mysql_monitor_email "$MYSQL_MONITOR_EMAIL" \
    --arg ert_tcprouter_static_ips "$ERT_TCPROUTER_STATIC_IPS" \
    --arg ert_mysql_static_ips "$ERT_MYSQL_STATIC_IPS" \
    --arg company_name "$COMPANY_NAME" \
    --arg ssh_static_ips "$SSH_STATIC_IPS" \
    --arg cert_pem "$SSL_CERT" \
    --arg private_key_pem "$SSL_PRIVATE_KEY" \
    --arg haproxy_forward_tls "$HAPROXY_FORWARD_TLS" \
    --arg haproxy_backend_ca "$HAPROXY_BACKEND_CA" \
    --arg router_ssl_ciphers "$ROUTER_SSL_CIPHERS" \
    --arg haproxy_ssl_ciphers "$HAPROXY_SSL_CIPHERS" \
    --arg disable_http_proxy "$DISABLE_HTTP_PROXY" \
    --arg smtp_from "$SMTP_FROM" \
    --arg smtp_address "$SMTP_ADDRESS" \
    --arg smtp_port "$SMTP_PORT" \
    --arg smtp_user "$SMTP_USER" \
    --arg smtp_password "$SMTP_PWD" \
    --arg smtp_auth_mechanism "$SMTP_AUTH_MECHANISM" \
    --arg enable_security_event_logging "$ENABLE_SECURITY_EVENT_LOGGING" \
    --arg syslog_host "$SYSLOG_HOST" \
    --arg syslog_drain_buffer_size "$SYSLOG_DRAIN_BUFFER_SIZE" \
    --arg syslog_port "$SYSLOG_PORT" \
    --arg syslog_protocol "$SYSLOG_PROTOCOL" \
    --arg authentication_mode "$AUTHENTICATION_MODE" \
    --arg ldap_url "$LDAP_URL" \
    --arg ldap_user "$LDAP_USER" \
    --arg ldap_password "$LDAP_PWD" \
    --arg ldap_search_base "$SEARCH_BASE" \
    --arg ldap_search_filter "$SEARCH_FILTER" \
    --arg ldap_group_search_base "$GROUP_SEARCH_BASE" \
    --arg ldap_group_search_filter "$GROUP_SEARCH_FILTER" \
    --arg ldap_mail_attr_name "$MAIL_ATTR_NAME" \
    --arg ldap_first_name_attr "$FIRST_NAME_ATTR" \
    --arg ldap_last_name_attr "$LAST_NAME_ATTR" \
    --arg saml_cert_pem "$SAML_SSL_CERT" \
    --arg saml_key_pem "$SAML_SSL_PRIVATE_KEY" \
    --arg mysql_backups "$MYSQL_BACKUPS" \
    --arg ert_mysql_lbr_ip "$ERT_MYSQL_LBR_IP" \
    --arg mysql_backups_s3_endpoint_url "$MYSQL_BACKUPS_S3_ENDPOINT_URL" \
    --arg mysql_backups_s3_bucket_name "$MYSQL_BACKUPS_S3_BUCKET_NAME" \
    --arg mysql_backups_s3_bucket_path "$MYSQL_BACKUPS_S3_BUCKET_PATH" \
    --arg mysql_backups_s3_access_key_id "$MYSQL_BACKUPS_S3_ACCESS_KEY_ID" \
    --arg mysql_backups_s3_secret_access_key "$MYSQL_BACKUPS_S3_SECRET_ACCESS_KEY" \
    --arg mysql_backups_s3_cron_schedule "$MYSQL_BACKUPS_S3_CRON_SCHEDULE" \
    --arg mysql_backups_scp_server "$MYSQL_BACKUPS_SCP_SERVER" \
    --arg mysql_backups_scp_port "$MYSQL_BACKUPS_SCP_PORT" \
    --arg mysql_backups_scp_user "$MYSQL_BACKUPS_SCP_USER" \
    --arg mysql_backups_scp_key "$MYSQL_BACKUPS_SCP_KEY" \
    --arg mysql_backups_scp_destination "$MYSQL_BACKUPS_SCP_DESTINATION" \
    --arg mysql_backups_scp_cron_schedule "$MYSQL_BACKUPS_SCP_CRON_SCHEDULE" \
    --arg container_networking_nw_cidr "$CONTAINER_NETWORKING_NW_CIDR" \
    --arg credhub_password "$CREDHUB_PASSWORD" \
    --arg container_networking_interface_plugin "$CONTAINER_NETWORKING_INTERFACE_PLUGIN" \
    --arg has_blobstore_internal_access_subnet "$has_blobstore_internal_access_subnet" \
    --arg blobstore_internal_access_subnet "$BLOBSTORE_INTERNAL_ACCESS_SUBNET" \
    '
    {
      ".properties.system_blobstore": {
        "value": "internal"
      },
      ".properties.logger_endpoint_port": {
        "value": $loggregator_endpoint_port
      },
      ".properties.security_acknowledgement": {
        "value": $security_acknowledgement
      },
      ".cloud_controller.system_domain": {
        "value": $system_domain
      },
      ".cloud_controller.apps_domain": {
        "value": $apps_domain
      },
      ".cloud_controller.default_quota_memory_limit_mb": {
        "value": $default_quota_memory_limit_in_mb
      },
      ".cloud_controller.default_quota_max_number_services": {
        "value": $default_quota_max_services_count
      },
      ".cloud_controller.allow_app_ssh_access": {
        "value": $allow_app_ssh_access
      },
      ".ha_proxy.static_ips": {
        "value": $ha_proxy_ips
      },
      ".ha_proxy.skip_cert_verify": {
        "value": $skip_cert_verify
      },
      ".router.disable_insecure_cookies": {
        "value": $disable_insecure_cookies
      },
      ".router.request_timeout_in_seconds": {
        "value": $router_request_timeout_seconds
      },
      ".mysql_monitor.recipient_email": {
        "value": $mysql_monitor_email
      },
      ".properties.push_apps_manager_company_name": {
        "value": $company_name
      },
      ".router.static_ips": {
        "value": $ert_gorouter_static_ips
      },
      ".tcp_router.static_ips": {
        "value": $ert_tcprouter_static_ips
      },
      ".diego_brain.static_ips": {
        "value": $ssh_static_ips
      },
      ".mysql_proxy.static_ips": {
        "value": $ert_mysql_static_ips
      },
      ".mysql_proxy.service_hostname": {
        "value": $ert_mysql_lbr_ip
      },
      ".properties.container_networking_interface_plugin": {
        "value": $container_networking_interface_plugin
      },
      
    }

    +
    
    # Blobstore access subnet
    if $has_blobstore_internal_access_subnet != "0" then
    {
        ".nfs_server.blobstore_internal_access_rules": {
        "value": $blobstore_internal_access_subnet
      }
    }
    else
    .
    end

    +

    # Route Services
    if $route_services == "enable" then
     {
       ".properties.route_services": {
         "value": "enable"
       },
       ".properties.route_services.enable.ignore_ssl_cert_verification": {
         "value": $ignore_ssl_cert
       }
     }
    else
     {
       ".properties.route_services": {
         "value": "disable"
       }
     }
    end

    +

    # TCP Routing
    if $tcp_routing == "enable" then
     {
       ".properties.tcp_routing": {
          "value": "enable"
        },
        ".properties.tcp_routing.enable.reservable_ports": {
          "value": $tcp_routing_ports
        }
      }
    else
      {
        ".properties.tcp_routing": {
          "value": "disable"
        }
      }
    end

    +

    # SSL Termination
    # SABHA - Change structure to take multiple certs.. for PCF 2.0
    {
      ".properties.networking_poe_ssl_certs": {
        "value": [ 
          {
            "name": "certificate",
            "certificate": {
              "cert_pem": $cert_pem,
              "private_key_pem": $private_key_pem
            }
          } 
        ]
      }
    }

    +

    # SABHA - Credhub integration
    {
     ".properties.credhub_key_encryption_passwords": {
        "value": [
          {                  
            "name": "primary-encryption-key",
            "key": { "secret": $credhub_password },
            "primary": true      
          }
        ]
      }
    }

    +
    
    # HAProxy Forward TLS
    if $haproxy_forward_tls == "enable" then
      {
        ".properties.haproxy_forward_tls": {
          "value": "enable"
        },
        ".properties.haproxy_forward_tls.enable.backend_ca": {
          "value": $haproxy_backend_ca
        }
      }
    else
      {
        ".properties.haproxy_forward_tls": {
          "value": "disable"
        }
      }
    end

    +

    {
      ".properties.routing_disable_http": {
        "value": $disable_http_proxy
      }
    }

    +

    # SSL/TLS Cipher Suites
    {
      ".properties.gorouter_ssl_ciphers": {
        "value": $router_ssl_ciphers
      },
      ".properties.haproxy_ssl_ciphers": {
        "value": $haproxy_ssl_ciphers
      }
    }

    +

    # SMTP Configuration
    if $smtp_address != "" then
      {
        ".properties.smtp_from": {
          "value": $smtp_from
        },
        ".properties.smtp_address": {
          "value": $smtp_address
        },
        ".properties.smtp_port": {
          "value": $smtp_port
        },
        ".properties.smtp_credentials": {
          "value": {
            "identity": $smtp_user,
            "password": $smtp_password
          }
        },
        ".properties.smtp_enable_starttls_auto": {
          "value": true
        },
        ".properties.smtp_auth_mechanism": {
          "value": $smtp_auth_mechanism
        }
      }
    else
      .
    end

    +

    # Syslog
    if $syslog_host != "" then
      {
        ".doppler.message_drain_buffer_size": {
          "value": $syslog_drain_buffer_size
        },
        ".cloud_controller.security_event_logging_enabled": {
          "value": $enable_security_event_logging
        },
        ".properties.syslog_host": {
          "value": $syslog_host
        },
        ".properties.syslog_port": {
          "value": $syslog_port
        },
        ".properties.syslog_protocol": {
          "value": $syslog_protocol
        }
      }
    else
      .
    end

    +

    # Authentication
    if $authentication_mode == "internal" then
      {
        ".properties.uaa": {
          "value": "internal"
        }
      }
    elif $authentication_mode == "ldap" then
      {
        ".properties.uaa": {
          "value": "ldap"
        },
        ".properties.uaa.ldap.url": {
          "value": $ldap_url
        },
        ".properties.uaa.ldap.credentials": {
          "value": {
            "identity": $ldap_user,
            "password": $ldap_password
          }
        },
        ".properties.uaa.ldap.search_base": {
          "value": $ldap_search_base
        },
        ".properties.uaa.ldap.search_filter": {
          "value": $ldap_search_filter
        },
        ".properties.uaa.ldap.group_search_base": {
          "value": $ldap_group_search_base
        },
        ".properties.uaa.ldap.group_search_filter": {
          "value": $ldap_group_search_filter
        },
        ".properties.uaa.ldap.mail_attribute_name": {
          "value": $ldap_mail_attr_name
        },
        ".properties.uaa.ldap.first_name_attribute": {
          "value": $ldap_first_name_attr
        },
        ".properties.uaa.ldap.last_name_attribute": {
          "value": $ldap_last_name_attr
        }
      }
    else
      .
    end

    +

    # UAA SAML Credentials
    {
      ".uaa.service_provider_key_credentials": {
        value: {
          "cert_pem": $saml_cert_pem,
          "private_key_pem": $saml_key_pem
        }
      }
    }

    +

    # MySQL Backups
    if $mysql_backups == "s3" then
      {
        ".properties.mysql_backups": {
          "value": "s3"
        },
        ".properties.mysql_backups.s3.endpoint_url":  {
          "value": $mysql_backups_s3_endpoint_url
        },
        ".properties.mysql_backups.s3.bucket_name":  {
          "value": $mysql_backups_s3_bucket_name
        },
        ".properties.mysql_backups.s3.bucket_path":  {
          "value": $mysql_backups_s3_bucket_path
        },
        ".properties.mysql_backups.s3.access_key_id":  {
          "value": $mysql_backups_s3_access_key_id
        },
        ".properties.mysql_backups.s3.secret_access_key":  {
          "value": $mysql_backups_s3_secret_access_key
        },
        ".properties.mysql_backups.s3.cron_schedule":  {
          "value": $mysql_backups_s3_cron_schedule
        }
      }
    elif $mysql_backups == "scp" then
      {
        ".properties.mysql_backups": {
          "value": "scp"
        },
        ".properties.mysql_backups.scp.server": {
          "value": $mysql_backups_scp_server
        },
        ".properties.mysql_backups.scp.port": {
          "value": $mysql_backups_scp_port
        },
        ".properties.mysql_backups.scp.user": {
          "value": $mysql_backups_scp_user
        },
        ".properties.mysql_backups.scp.key": {
          "value": $mysql_backups_scp_key
        },
        ".properties.mysql_backups.scp.destination": {
          "value": $mysql_backups_scp_destination
        },
        ".properties.mysql_backups.scp.cron_schedule" : {
          "value": $mysql_backups_scp_cron_schedule
        }
      }
    else
      .
    end
    '
)

## SABHA - removed cidr
# ".properties.container_networking_network_cidr": {
#         "value": $container_networking_nw_cidr
#       },
      

cf_network=$(
  jq -n \
    --arg network_name "$NETWORK_NAME" \
    --arg other_azs "$AZS_ERT" \
    --arg singleton_az "$AZ_ERT_SINGLETON" \
    '
    {
      "network": {
        "name": $network_name
      },
      "other_availability_zones": ($other_azs | split(",") | map({name: .})),
      "singleton_availability_zone": {
        "name": $singleton_az
      }
    }
    '    
    
)

cf_resources=$(
  jq -n \
    --arg iaas "vsphere" \
    --argjson consul_server_instances $CONSUL_SERVER_INSTANCES \
    --argjson nats_instances $NATS_INSTANCES \
    --argjson nfs_server_instances $NFS_SERVER_INSTANCES \
    --argjson mysql_proxy_instances $MYSQL_PROXY_INSTANCES \
    --argjson mysql_instances $MYSQL_INSTANCES \
    --argjson backup_prepare_instances $BACKUP_PREPARE_INSTANCES \
    --argjson diego_database_instances $DIEGO_DATABASE_INSTANCES \
    --argjson uaa_instances $UAA_INSTANCES \
    --argjson cloud_controller_instances $CLOUD_CONTROLLER_INSTANCES \
    --argjson ha_proxy_instances $HA_PROXY_INSTANCES \
    --argjson router_instances $ROUTER_INSTANCES \
    --argjson mysql_monitor_instances $MYSQL_MONITOR_INSTANCES \
    --argjson clock_global_instances $CLOCK_GLOBAL_INSTANCES \
    --argjson cloud_controller_worker_instances $CLOUD_CONTROLLER_WORKER_INSTANCES \
    --argjson diego_brain_instances $DIEGO_BRAIN_INSTANCES \
    --argjson diego_cell_instances $DIEGO_CELL_INSTANCES \
    --argjson loggregator_tc_instances $LOGGREGATOR_TC_INSTANCES \
    --argjson tcp_router_instances $TCP_ROUTER_INSTANCES \
    --argjson syslog_adapter_instances $SYSLOG_ADAPTER_INSTANCES \
    --argjson doppler_instances $DOPPLER_INSTANCES \
    --argjson internet_connected $INTERNET_CONNECTED \
    '
    {
      "consul_server": { "instances": $consul_server_instances },
      "nats": { "instances": $nats_instances },
      "nfs_server": { "instances": $nfs_server_instances },
      "mysql_proxy": { "instances": $mysql_proxy_instances },
      "mysql": { "instances": $mysql_instances },
      "backup-prepare": { "instances": $backup_prepare_instances },
      "diego_database": { "instances": $diego_database_instances },
      "uaa": { "instances": $uaa_instances },
      "cloud_controller": { "instances": $cloud_controller_instances },
      "ha_proxy": { "instances": $ha_proxy_instances },
      "router": { "instances": $router_instances },
      "mysql_monitor": { "instances": $mysql_monitor_instances },
      "clock_global": { "instances": $clock_global_instances },
      "cloud_controller_worker": { "instances": $cloud_controller_worker_instances },
      "diego_brain": { "instances": $diego_brain_instances },
      "diego_cell": { "instances": $diego_cell_instances },
      "loggregator_trafficcontroller": { "instances": $loggregator_tc_instances },
      "tcp_router": { "instances": $tcp_router_instances },
      "syslog_adapter": { "instances": $syslog_adapter_instances },
      "doppler": { "instances": $doppler_instances }
    }
    '
)

om \
    -t https://$OPS_MGR_HOST \
    -u $OPS_MGR_USR \
    -p $OPS_MGR_PWD \
    -k configure-product \
    -n cf \
    -p "$cf_properties" \
    -pn "$cf_network" \
    -pr "$cf_resources"



# Set Errands to on Demand for 1.10
if [ "$IS_ERRAND_WHEN_CHANGED_ENABLED" == "true" ]; then
  echo "applying errand configuration"
  sleep 6
  ERT_ERRANDS=$(cat <<-EOF
{"errands":[
  {"name":"smoke_tests","post_deploy":"when-changed"},
  {"name":"push-usage-service","post_deploy":"when-changed"},
  {"name":"push-apps-manager","post_deploy":"when-changed"},
  {"name":"deploy-notifications","post_deploy":"when-changed"},
  {"name":"deploy-notifications-ui","post_deploy":"when-changed"},
  {"name":"push-pivotal-account","post_deploy":"when-changed"},
  {"name":"deploy-autoscaling","post_deploy":"when-changed"},
  {"name":"register-broker","post_deploy":"when-changed"},
  {"name":"nfsbrokerpush","post_deploy":"when-changed"}
]}
EOF
)

  om \
      -t https://$OPS_MGR_HOST \
      -u $OPS_MGR_USR \
      -p $OPS_MGR_PWD \
      -k curl -p "/api/v0/staged/products/$PRODUCT_GUID/errands" \
      -x PUT -d "$ERT_ERRANDS"

fi

# if nsx is not enabled, skip remaining steps
if [ "$IS_NSX_ENABLED" == "null" -o "$IS_NSX_ENABLED" == "" ]; then
  exit
fi

# Proceed if NSX is enabled on Bosh Director
# Support NSX LBR Integration

# $ISO_TILE_JOBS_REQUIRING_LBR comes filled by nsx-edge-gen list command
# Sample: ERT_TILE_JOBS_REQUIRING_LBR='mysql_proxy,tcp_router,router,diego_brain'
JOBS_REQUIRING_LBR=$ERT_TILE_JOBS_REQUIRING_LBR

# Change to pattern for grep
JOBS_REQUIRING_LBR_PATTERN=$(echo $JOBS_REQUIRING_LBR | sed -e 's/,/\\|/g')

# Get job guids for deployment (from staged product)
om -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
                              curl -p "/api/v0/staged/products/${PRODUCT_GUID}/jobs" 2>/dev/null \
                              | jq '.[] | .[] ' > /tmp/jobs_list.log

for job_guid in $(cat /tmp/jobs_list.log | jq '.guid' | tr -d '"')
do
  job_name=$(cat /tmp/jobs_list.log | grep -B1 $job_guid | grep name | awk -F '"' '{print $4}')
  job_name_upper=$(echo ${job_name^^} | sed -e 's/-/_/')
  
  # Check for security group defined for the given job from Env
  # Expecting only one security group env variable per job (can have a comma separated list)
  SECURITY_GROUP=$(env | grep "TILE_ERT_${job_name_upper}_SECURITY_GROUP" | awk -F '=' '{print $2}')

  match=$(echo $job_name | grep -e $JOBS_REQUIRING_LBR_PATTERN  || true)
  if [ "$match" != "" -o "$SECURITY_GROUP" != "" ]; then
    echo "$job_name requires Loadbalancer or security group..."
    
    # Check if User has specified their own security group
    # Club that with an auto-security group based on product guid by Bosh 
    # for grouping all vms with the same security group
    if [ "$SECURITY_GROUP" != "" ]; then
      SECURITY_GROUP="${SECURITY_GROUP},${PRODUCT_GUID}"
    else
      SECURITY_GROUP=${PRODUCT_GUID}
    fi  

    # The associative array comes from sourcing the /tmp/jobs_lbr_map.out file
    # filled earlier by nsx-edge-gen list command
    # Sample associative array content:
    # ERT_TILE_JOBS_LBR_MAP=( ["mysql_proxy"]="$ERT_MYSQL_LBR_DETAILS" ["tcp_router"]="$ERT_TCPROUTER_LBR_DETAILS" 
    # .. ["diego_brain"]="$SSH_LBR_DETAILS"  ["router"]="$ERT_GOROUTER_LBR_DETAILS" )
    # SSH_LBR_DETAILS=[diego_brain]="esg-sabha6:VIP-diego-brain-tcp-21:diego-brain21-Pool:2222"
    LBR_DETAILS=${ERT_TILE_JOBS_LBR_MAP[$job_name]}

    RESOURCE_CONFIG=$(om -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
                      curl -p "/api/v0/staged/products/${PRODUCT_GUID}/jobs/${job_guid}/resource_config" \
                      2>/dev/null)
    #echo "Resource config : $RESOURCE_CONFIG"
    # Remove trailing brace to add additional elements
    # Remove also any empty nsx_security_groups
    # Sample RESOURCE_CONFIG with nsx_security_group comes middle with ','
    # { "instance_type": { "id": "automatic" },
    #   "instances": 1,
    #   "nsx_security_groups": null,
    #   "persistent_disk": { "size_mb": "1024" }
    # }
    # or nsx_security_group comes last without ','
    # { "instance_type": { "id": "automatic" },
    #   "instances": 1,
    #   "nsx_security_groups": null
    # }
    # Strip the ending brace and also "nsx_security_group": null


    nsx_lbr_payload_json='{ "nsx_lbs": [ ] }'

    index=1
    for variable in $(echo $LBR_DETAILS)
    do
      edge_name=$(echo $variable | awk -F ':' '{print $1}')
      lbr_name=$(echo $variable  | awk -F ':' '{print $2}')
      pool_name=$(echo $variable | awk -F ':' '{print $3}')
      port=$(echo $variable | awk -F ':' '{print $4}')
      monitor_port=$(echo $variable | awk -F ':' '{print $5}')
      echo "ESG: $edge_name, LBR: $lbr_name, Pool: $pool_name, Port: $port, Monitor port: $monitor_port"
      
      # Create a security group with Product Guid and job name for lbr security grp
      job_security_grp=${PRODUCT_GUID}-${job_name}

      #ENTRY="{ \"edge_name\": \"$edge_name\", \"pool_name\": \"$pool_name\", \"port\": \"$port\", \"security_group\": \"$job_security_grp\" }"
      #ENTRY="{ \"edge_name\": \"$edge_name\", \"pool_name\": \"$pool_name\", \"port\": \"$port\", \"monitor_port\": \"$monitor_port\", \"security_group\": \"$job_security_grp\" }"
      #echo "Created lbr entry for job: $job_guid with value: $ENTRY"

      ENTRY=$(jq -n \
                  --arg edge_name $edge_name \
                  --arg pool_name $pool_name \
                  --argjson port $port \
                  --arg monitor_port $monitor_port \
                  --arg security_group "$job_security_grp" \
                  '{
                     "edge_name": $edge_name,
                     "pool_name": $pool_name,
                     "port": $port,
                     "security_group": $security_group
                   }
                   +
                   if $monitor_port != null and $monitor_port != "None" then
                   {
                      "monitor_port": $monitor_port
                   }
                   else
                    .
                   end
              ')

      nsx_lbr_payload_json=$(echo $nsx_lbr_payload_json \
                                | jq --argjson new_entry "$ENTRY" \
                                '.nsx_lbs += [$new_entry] ')
      
      #index=$(expr $index + 1)
    done

    nsx_security_group_json=$(jq -n \
                              --arg nsx_security_groups $SECURITY_GROUP \
                              '{ "nsx_security_groups": ($nsx_security_groups | split(",") ) }')

    #echo "Job: $job_name with GUID: $job_guid and NSX_LBR_PAYLOAD : $NSX_LBR_PAYLOAD"
    echo "Job: $job_name with GUID: $job_guid has SG: $nsx_security_group_json and NSX_LBR_PAYLOAD : $nsx_lbr_payload_json"
    
    #UPDATED_RESOURCE_CONFIG=$(echo "$RESOURCE_CONFIG \"nsx_security_groups\": [ $SECURITY_GROUP ], $NSX_LBR_PAYLOAD }")
    UPDATED_RESOURCE_CONFIG=$( echo $RESOURCE_CONFIG \
                              | jq  \
                              --argjson nsx_lbr_payload "$nsx_lbr_payload_json" \
                              --argjson nsx_security_groups "$nsx_security_group_json" \
                              ' . |= . + $nsx_security_groups +  $nsx_lbr_payload ')
    echo "Job: $job_name with GUID: $job_guid and RESOURCE_CONFIG : $UPDATED_RESOURCE_CONFIG"

    # Register job with NSX Pool in Ops Mgr (gets passed to Bosh)
    om \
        -t https://$OPS_MGR_HOST \
        -k -u $OPS_MGR_USR \
        -p $OPS_MGR_PWD  \
        curl -p "/api/v0/staged/products/${PRODUCT_GUID}/jobs/${job_guid}/resource_config"  \
        -x PUT  -d "${UPDATED_RESOURCE_CONFIG}" 2>/dev/null

    # final structure
    # {
    #   "instance_type": {
    #     "id": "automatic"
    #   },
    #   "instances": 1,
    #   "persistent_disk": {
    #     "size_mb": "automatic"
    #   },
    #   "nsx_security_groups": [
    #     "cf-a7e3e3f819a68a3ee869"
    #   ],
    #   "nsx_lbs": [
    #     {
    #       "edge_name": "esg-sabha-test",
    #       "pool_name": "tcp-router31-Pool",
    #       "security_group": "cf-a7e3e3f819a68a3ee869-tcp_router",
    #       "port": "5000"
    #     }
    #   ]
    # }

  fi
done

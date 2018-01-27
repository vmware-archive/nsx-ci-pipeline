#!/bin/bash -e

chmod +x om-cli/om-linux

export ROOT_DIR=`pwd`
export PATH=$PATH:$ROOT_DIR/om-cli
source $ROOT_DIR/concourse-vsphere/functions/check_versions.sh

source $ROOT_DIR/concourse-vsphere/functions/check_versions.sh

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

  IS_NSX_ENABLED=$(om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k \
               curl -p "/api/v0/deployed/director/manifest" 2>/dev/null | jq '.cloud_provider.properties.vcenter.nsx' || true )

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

om-linux \
  -t https://$OPS_MGR_HOST \
  --skip-ssl-validation \
  -u $OPS_MGR_USR \
  -p $OPS_MGR_PWD \
  -k stage-product \
  -p $PRODUCT_NAME \
  -v $PRODUCT_VERSION

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

  CERTIFICATES=`om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl -p "/api/v0/certificates/generate" -x POST -d "$DOMAINS"`

  export SSL_CERT=`echo $CERTIFICATES | jq '.certificate'`
  export SSL_PRIVATE_KEY=`echo $CERTIFICATES | jq '.key'`
  # echo "SSL_CERT is" $SSL_CERT
  # echo "SSL_PRIVATE_KEY is" $SSL_PRIVATE_KEY
else
  echo "Using certs passed in YML"
fi




# API calls using OM Cli
# om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k  available-products -n cf
# output:
# +------+---------+
# | NAME | VERSION |
# +------+---------+
# | cf   | 1.11.0  |
# +------+---------+

# om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl -p  "/api/installation_settings"
# output:
# full dump of all properties for all products

# om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl -p  "/api/v0/staged/products/{app-guid}/properties"
# output: dump of properties for a specific staged product

# To get the bosh cloud config contianing networks and azs:
# om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl -p "/api/v0/deployed/cloud_config" | jq .cloud_config.networks```
# om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl -p "/api/v0/deployed/cloud_config" | jq .cloud_config.azs```

# Just bosh director manifest
# om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl -p "/api/v0/deployed/director/manifest"

# Get the installation details
# om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k  curl -p "/api/installation_settings" | jq .infrastructure.networks

CF_PROPERTIES=$(cat <<-EOF
{
  ".properties.logger_endpoint_port": {
    "value": "$LOGGREGATOR_ENDPOINT_PORT"
  },  
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
  ".properties.system_blobstore": {
    "value": "internal"
  },
  ".properties.mysql_backups": {
    "value": "disable"
  },
  ".mysql_proxy.service_hostname": {
    "value": "$ERT_MYSQL_LBR_IP"
  },
EOF
)

if [[ "$SSL_TERMINATION" == "haproxy" ]]; then

echo "Terminating SSL on HAProxy"
CF_PROPERTIES=$(cat <<-EOF
$CF_PROPERTIES
  ".properties.networking_point_of_entry": {
    "value": "haproxy"
  },
  ".properties.networking_point_of_entry.haproxy.ssl_rsa_certificate": {
    "value": {
      "cert_pem": $SSL_CERT,
      "private_key_pem": $SSL_PRIVATE_KEY
    }
  },
EOF
)

elif [[ "$SSL_TERMINATION" == "external_ssl" ]]; then
echo "Terminating SSL on GoRouters"

CF_PROPERTIES=$(cat <<-EOF
$CF_PROPERTIES
  ".properties.networking_point_of_entry": {
    "value": "external_ssl"
  },
  ".properties.networking_point_of_entry.external_ssl.ssl_rsa_certificate": {
    "value": {
      "cert_pem": $SSL_CERT,
      "private_key_pem": $SSL_PRIVATE_KEY
    }
  },
EOF
)

elif [[ "$SSL_TERMINATION" == "external_non_ssl" ]]; then
echo "Terminating SSL on Load Balancers"
CF_PROPERTIES=$(cat <<-EOF
$CF_PROPERTIES
  ".properties.networking_point_of_entry": {
    "value": "external_non_ssl"
  },

EOF
)

fi

# Add the static ips to list above if nsx not enabled in Bosh director 
# If nsx enabled, a security group would be dynamically created with vms 
# and associated with the pool by Bosh
if [ "$IS_NSX_ENABLED" == "null" -o "$IS_NSX_ENABLED" == "" ]; then

  CF_PROPERTIES=$(cat <<-EOF
$CF_PROPERTIES
  ".router.static_ips": {
    "value": "$ERT_GOROUTER_STATIC_IPS"
  },
  ".tcp_router.static_ips": {
    "value": "$ERT_TCPROUTER_STATIC_IPS"
  },
  ".diego_brain.static_ips": {
    "value": "$SSH_STATIC_IPS"
  },
  ".mysql_proxy.static_ips": {
    "value": "$ERT_MYSQL_STATIC_IPS"
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
  ".router.disable_insecure_cookies": {
    "value": false
  },
  ".router.request_timeout_in_seconds": {
    "value": 900
  },
  ".mysql_monitor.recipient_email": {
    "value": "$MYSQL_MONITOR_EMAIL"
  },
  ".diego_cell.garden_network_mtu": {
    "value": 1454
  },
  ".doppler.message_drain_buffer_size": {
    "value": 10000
  },
  ".push-apps-manager.company_name": {
    "value": "${NSX_APPS_MGR_NAME}"
  },
EOF
)



# PCF supports C2C
if [ "$SUPPORTS_C2C" == "true" ]; then

  # If user wants C2C enabled, then add additional properties
  if [ "$TILE_ERT_ENABLE_C2C" == "enable" ]; then
    CF_PROPERTIES=$(cat <<-EOF
$CF_PROPERTIES
  ".properties.container_networking.enable.network_cidr": {
      "value": "$TILE_ERT_C2C_NETWORK_CIDR"
  },
  ".properties.container_networking.enable.vtep_port": {
    "value": "$TILE_ERT_C2C_VTEP_PORT"
  }
}
EOF
)
  else
    # User does not want c2c
    CF_PROPERTIES=$(cat <<-EOF
$CF_PROPERTIES
  ".properties.container_networking.disable.garden_network_pool": {
    "value": "10.254.0.0/22"
  }
}
EOF
)
  fi
  # End of SUPPORTS_C2C
else  
  # Older version, no C2C support
  CF_PROPERTIES=$(cat <<-EOF
$CF_PROPERTIES
  ".diego_cell.garden_network_pool": {
      "value": "10.254.0.0/22"
    }
}
EOF
)
fi
# End of PROPERTIES block

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

om-linux \
    -t https://$OPS_MGR_HOST \
    -u $OPS_MGR_USR \
    -p $OPS_MGR_PWD \
    -k configure-product \
    -n cf \
    -p "$CF_PROPERTIES" \
    -pn "$CF_NETWORK" \
    -pr "$CF_RESOURCES"


if [[ "$AUTHENTICATION_MODE" == "internal" ]]; then
echo "Configuring Internal Authentication in ERT..."
CF_AUTH_PROPERTIES=$(cat <<-EOF
{
  ".properties.uaa": {
    "value": "$AUTHENTICATION_MODE"
  },
  ".uaa.service_provider_key_credentials": {
        "value": {
          "cert_pem": "",
          "private_key_pem": ""
        }
  }
}
EOF
)

elif [[ "$AUTHENTICATION_MODE" == "ldap" ]]; then
echo "Configuring LDAP Authentication in ERT..."
CF_AUTH_PROPERTIES=$(cat <<-EOF
{
  ".properties.uaa": {
    "value": "ldap"
  },
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
  ".uaa.service_provider_key_credentials": {
        "value": {
          "cert_pem": "",
          "private_key_pem": ""
        }
  }  
}
EOF
)

fi

saml_cert_domains=$(cat <<-EOF
  {"domains": ["*.$SYSTEM_DOMAIN", "*.login.$SYSTEM_DOMAIN", "*.uaa.$SYSTEM_DOMAIN"] }
EOF
)

saml_cert_response=`om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl -p "$OPS_MGR_GENERATE_SSL_ENDPOINT" -x POST -d "$saml_cert_domains"`

saml_cert_pem=$(echo $saml_cert_response | jq --raw-output '.certificate')
saml_key_pem=$(echo $saml_cert_response | jq --raw-output '.key')

cat > saml_auth_filters <<'EOF'
.".uaa.service_provider_key_credentials".value = {
  "cert_pem": $saml_cert_pem,
  "private_key_pem": $saml_key_pem
}
EOF

CF_AUTH_WITH_SAML_CERTS=$(echo $CF_AUTH_PROPERTIES | jq \
  --arg saml_cert_pem "$saml_cert_pem" \
  --arg saml_key_pem "$saml_key_pem" \
  --from-file saml_auth_filters \
  --raw-output)

om-linux \
    -t https://$OPS_MGR_HOST \
    -u $OPS_MGR_USR \
    -p $OPS_MGR_PWD \
    -k configure-product \
    -n cf \
    -p "$CF_AUTH_WITH_SAML_CERTS"

if [[ ! -z "$SYSLOG_HOST" ]]; then

echo "Configuring Syslog in ERT..."

CF_SYSLOG_PROPERTIES=$(cat <<-EOF
{
  ".doppler.message_drain_buffer_size": {
    "value": $SYSLOG_DRAIN_BUFFER_SIZE
  },
  ".cloud_controller.security_event_logging_enabled": {
    "value": $ENABLE_SECURITY_EVENT_LOGGING
  },
  ".properties.syslog_host": {
    "value": "$SYSLOG_HOST"
  },
  ".properties.syslog_port": {
    "value": "$SYSLOG_PORT"
  },
  ".properties.syslog_protocol": {
    "value": "$SYSLOG_PROTOCOL"
  }
}
EOF
)

om-linux \
    -t https://$OPS_MGR_HOST \
    -u $OPS_MGR_USR \
    -p $OPS_MGR_PWD \
    -k configure-product \
    -n cf \
    -p "$CF_SYSLOG_PROPERTIES"

fi

if [[ ! -z "$SMTP_ADDRESS" ]]; then

echo "Configuring SMTP in ERT..."

CF_SMTP_PROPERTIES=$(cat <<-EOF
{
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
  }
}
EOF
)

om-linux \
    -t https://$OPS_MGR_HOST \
    -u $OPS_MGR_USR \
    -p $OPS_MGR_PWD \
    -k configure-product \
    -n cf \
    -p "$CF_SMTP_PROPERTIES"

fi

check_staged_product_guid "cf-"

# Set Errands to on Demand for 1.10
if [ "$IS_ERRAND_WHEN_CHANGED_ENABLED" == "true" ]; then
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

  om-linux \
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
om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
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
    echo "$job requires Loadbalancer or security group..."
    
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

    RESOURCE_CONFIG=$(om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
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
                              '{ "nsx_security_groups": [  ($nsx_security_groups | split(",") ) ] }')
                              
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
    om-linux \
        -t https://$OPS_MGR_HOST \
        -k -u $OPS_MGR_USR \
        -p $OPS_MGR_PWD  \
        curl -p "/api/v0/staged/products/${PRODUCT_GUID}/jobs/${job_guid}/resource_config"  \
        -x PUT  -d "${UPDATED_RESOURCE_CONFIG}"

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



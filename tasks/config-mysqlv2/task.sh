#!/bin/bash -e

export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-ci-pipeline/functions/check_versions.sh
source $ROOT_DIR/nsx-ci-pipeline/functions/check_null_variables.sh

export SCRIPT_DIR=$(dirname $0)
export NSX_GEN_OUTPUT_DIR=${ROOT_DIR}/nsx-gen-output
export NSX_GEN_OUTPUT=${NSX_GEN_OUTPUT_DIR}/nsx-gen-out.log
export NSX_GEN_UTIL=${NSX_GEN_OUTPUT_DIR}/nsx_parse_util.sh

if [ -e "${NSX_GEN_OUTPUT}" ]; then
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

# Check if Bosh Director is v1.11 or higher
check_bosh_version
check_available_product_version "pivotal-mysql"

export IS_ERRAND_WHEN_CHANGED_ENABLED=false
if [ $BOSH_MAJOR_VERSION -le 1 ]; then
  if [ $BOSH_MINOR_VERSION -ge 10 ]; then
    export IS_ERRAND_WHEN_CHANGED_ENABLED=true
  fi
else
  export IS_ERRAND_WHEN_CHANGED_ENABLED=true
fi

om \
    -t https://$OPS_MGR_HOST \
    -u $OPS_MGR_USR \
    -p $OPS_MGR_PWD  \
    -k stage-product \
    -p $PRODUCT_NAME \
    -v $PRODUCT_VERSION

check_staged_product_guid "pivotal-mysql"

prod_network=$(
  jq -n \
    --arg network_name "$NETWORK_NAME" \
    --arg other_azs "$TILE_AZS_MYSQL" \
    --arg singleton_az "$TILE_AZ_MYSQL_SINGLETON" \
    --arg service_network_name "$SERVICE_NETWORK_NAME" \
    '
    {
      "network": {
        "name": $network_name
      },
      "service_network": {
        "name": $service_network_name
      },
      "other_availability_zones": ($other_azs | split(",") | map({name: .})),
      "singleton_availability_zone": {
        "name": $singleton_az
      }
    }
    '
)

# Add the static ips to list above if nsx not enabled in Bosh director
# If nsx enabled, a security group would be dynamically created with vms
# and associated with the pool by Bosh
if [ "$IS_NSX_ENABLED" == "null" -o "$IS_NSX_ENABLED" == "" ]; then
  PROPERTIES=$(cat <<-EOF
{
  ".proxy.static_ips": {
    "value": "$MYSQL_TILE_STATIC_IPS"
  },
EOF
)
else
  PROPERTIES="{"
fi

# Check if bosh director is v1.11+
export SUPPORTS_SYSLOG=false
if [ $BOSH_MAJOR_VERSION -le 1 ]; then
  if [ $BOSH_MINOR_VERSION -ge 11 ]; then
    SUPPORTS_SYSLOG=true
  fi
else
  export SUPPORTS_SYSLOG=true
fi

# Check if the tile metadata supports syslog
if [ "$SUPPORTS_SYSLOG" == "true" ]; then

  MYSQL_TILE_PROPERTIES=$(om -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
                      curl -p "/api/v0/staged/products/${PRODUCT_GUID}/properties" \
                      2>/dev/null)
  supports_syslog=$(echo $MYSQL_TILE_PROPERTIES | grep properties.syslog || true)
  if [ "$supports_syslog" != "" ]; then
    PROPERTIES=$(cat <<-EOF
$PROPERTIES
  ".properties.syslog": {
    "value": "disabled"
  },
EOF
)
  fi
fi


PROPERTIES=$(cat <<-EOF
$PROPERTIES
  ".cf-mysql-broker.bind_hostname": {
    "value": "$MYSQL_TILE_LBR_IP"
  },
  ".properties.optional_protections": {
    "value": "enable"
  },
  ".properties.optional_protections.enable.recipient_email": {
    "value": "$TILE_MYSQL_MONITOR_EMAIL"
  }
}
EOF
)

#export TILE_AZS_MYSQLV2="az1,az2" TILE_MYSQLV2_PLAN1_NAME=plan1 TILE_MYSQLV2_PLAN1_DESCRIPTION=testplan1 \
#TILE_MYSQLV2_PLAN1_INSTANCE_LIMIT=30 TILE_MYSQLV2_PLAN1_ACCESS=enable TILE_MYSQLV2_PLAN1_MULTI_NODE_DEPLOYMENT=enable \
#TILE_MYSQLV2_PLAN1_VM_TYPE=medium TILE_MYSQLV2_PLAN1_PERSISTENT_DISK_SIZE=10240

backup_option=$(echo "${TILE_MYSQLV2_BACKUP_OPTION,,}")
elif [[ "$backup_option" =~ "s3" -o  "$backup_option" =~ "ceph" ]]; then
  enabled_backup="s3"
elif [[ "$backup_option" =~ "gcs" ]]; then
  enabled_backup="gcs"
elif [[ "$backup_option" =~ "az" ]]; then
  enabled_backup="azure"
elif [[ "$backup_option" =~ "scp" ]]; then
  enabled_backup="scp"
else
  enabled_backup="disabled"
fi

if [ "$enabled_backup" != "disabled" ]; then
  if [ "$TILE_MYSQLV2_BACKUP_EMAIL_ALERTS" == "" ]; then
    backup_email_alerts=false
  else
    backup_email_alerts=true
  fi
fi

prod_properties=$(
  jq -n \
    --arg other_azs $TILE_AZS_MYSQLV2 \
    --arg plan1_name "$TILE_MYSQLV2_PLAN1_NAME" \
    --arg plan1_description $TILE_MYSQLV2_PLAN1_DESCRIPTION \
    --argjson plan1_instance_limit $TILE_MYSQLV2_PLAN1_INSTANCE_LIMIT \
    --arg plan1_access "$TILE_MYSQLV2_PLAN1_ACCESS" \
    --arg plan1_multi_node_deployment "$TILE_MYSQLV2_PLAN1_MULTI_NODE_DEPLOYMENT" \
    --arg plan1_vm_type "$TILE_MYSQLV2_PLAN1_VM_TYPE" \
    --arg plan1_disk_size "$TILE_MYSQLV2_PLAN1_PERSISTENT_DISK_SIZE" \
    --arg has_plan2_enabled "$TILE_MYSQLV2_PLAN2_ENABLED" \
    --arg plan2_name "$TILE_MYSQLV2_PLAN2_NAME" \
    --arg plan2_description $TILE_MYSQLV2_PLAN2_DESCRIPTION \
    --argjson plan2_instance_limit $TILE_MYSQLV2_PLAN2_INSTANCE_LIMIT \
    --arg plan2_access "$TILE_MYSQLV2_PLAN2_ACCESS" \
    --arg plan2_multi_node_deployment "$TILE_MYSQLV2_PLAN2_MULTI_NODE_DEPLOYMENT" \
    --arg plan2_vm_type "$TILE_MYSQLV2_PLAN2_VM_TYPE" \
    --arg plan2_disk_size "$TILE_MYSQLV2_PLAN2_PERSISTENT_DISK_SIZE" \
    --arg has_plan3_enabled "$TILE_MYSQLV2_PLAN3_ENABLED" \
    --arg plan3_name "$TILE_MYSQLV2_PLAN3_NAME" \
    --arg plan3_description $TILE_MYSQLV2_PLAN3_DESCRIPTION \
    --argjson plan3_instance_limit $TILE_MYSQLV2_PLAN3_INSTANCE_LIMIT \
    --arg plan3_access "$TILE_MYSQLV2_PLAN3_ACCESS" \
    --arg plan3_multi_node_deployment "$TILE_MYSQLV2_PLAN3_MULTI_NODE_DEPLOYMENT" \
    --arg plan3_vm_type "$TILE_MYSQLV2_PLAN3_VM_TYPE" \
    --arg plan3_disk_size "$TILE_MYSQLV2_PLAN3_PERSISTENT_DISK_SIZE" \
    --arg has_plan4_enabled "$TILE_MYSQLV2_PLAN4_ENABLED" \
    --arg plan4_name "$TILE_MYSQLV2_PLAN4_NAME" \
    --arg plan4_description $TILE_MYSQLV2_PLAN4_DESCRIPTION \
    --argjson plan4_instance_limit $TILE_MYSQLV2_PLAN4_INSTANCE_LIMIT \
    --arg plan4_access "$TILE_MYSQLV2_PLAN4_ACCESS" \
    --arg plan4_multi_node_deployment "$TILE_MYSQLV2_PLAN4_MULTI_NODE_DEPLOYMENT" \
    --arg plan4_vm_type "$TILE_MYSQLV2_PLAN4_VM_TYPE" \
    --arg plan4_disk_size "$TILE_MYSQLV2_PLAN4_PERSISTENT_DISK_SIZE" \
    --arg has_plan5_enabled "$TILE_MYSQLV2_PLAN5_ENABLED" \
    --arg plan5_name "$TILE_MYSQLV2_PLAN5_NAME" \
    --arg plan5_description $TILE_MYSQLV2_PLAN5_DESCRIPTION \
    --argjson plan5_instance_limit $TILE_MYSQLV2_PLAN5_INSTANCE_LIMIT \
    --arg plan5_access "$TILE_MYSQLV2_PLAN5_ACCESS" \
    --arg plan5_multi_node_deployment "$TILE_MYSQLV2_PLAN5_MULTI_NODE_DEPLOYMENT" \
    --arg plan5_vm_type "$TILE_MYSQLV2_PLAN5_VM_TYPE" \
    --arg plan5_disk_size "$TILE_MYSQLV2_PLAN5_PERSISTENT_DISK_SIZE" \
    --arg enabled_backup "$enabled_backup" \
    --arg backup_cron_schedule "$$TILE_MYSQLV2_BACKUP_CRON_SCHEDULE" \
    --argjson backup_email_alerts $backup_email_alerts \
    --arg tile_mysqlv2_backup_s3_access_id          "$TILE_MYSQLV2_BACKUP_S3_ACCESS_ID" \
    --arg tile_mysqlv2_backup_s3_access_key         "$TILE_MYSQLV2_BACKUP_S3_ACCESS_KEY" \
    --arg tile_mysqlv2_backup_s3_endpoint           "$TILE_MYSQLV2_BACKUP_S3_ENDPOINT" \
    --arg tile_mysqlv2_backup_s3_bucket             "$TILE_MYSQLV2_BACKUP_S3_BUCKET" \
    --arg tile_mysqlv2_backup_s3_path               "$TILE_MYSQLV2_BACKUP_S3_PATH" \
    --arg tile_mysqlv2_backup_s3_region             "$TILE_MYSQLV2_BACKUP_S3_REGION" \
    --arg tile_mysqlv2_backup_azure_account         "$TILE_MYSQLV2_BACKUP_AZURE_ACCOUNT" \
    --arg tile_mysqlv2_backup_azure_key             "$TILE_MYSQLV2_BACKUP_AZURE_KEY" \
    --arg tile_mysqlv2_backup_azure_path            "$TILE_MYSQLV2_BACKUP_AZURE_PATH" \
    --arg tile_mysqlv2_backup_azure_blobstore       "$TILE_MYSQLV2_BACKUP_AZURE_BLOBSTORE" \
    --arg tile_mysqlv2_backup_scp_user              "$TILE_MYSQLV2_BACKUP_SCP_USER" \
    --arg tile_mysqlv2_backup_scp_server            "$TILE_MYSQLV2_BACKUP_SCP_SERVER" \
    --arg tile_mysqlv2_backup_scp_destination       "$TILE_MYSQLV2_BACKUP_SCP_DESTINATION" \
    --arg tile_mysqlv2_backup_scp_fingerprint       "$TILE_MYSQLV2_BACKUP_SCP_FINGERPRINT" \
    --arg tile_mysqlv2_backup_scp_key               "$TILE_MYSQLV2_BACKUP_SCP_KEY" \
    --argjson tile_mysqlv2_backup_scp_port          ${TILE_MYSQLV2_BACKUP_SCP_PORT:-443} \
    --arg tile_mysqlv2_backup_gcs_project           "$TILE_MYSQLV2_BACKUP_GCS_PROJECT" \
    --arg tile_mysqlv2_backup_gcs_bucket            "$TILE_MYSQLV2_BACKUP_GCS_BUCKET" \
    --arg tile_mysqlv2_backup_gcs_service_account   "$TILE_MYSQLV2_BACKUP_GCS_SERVICE_ACCOUNT" \
    '
    {
     ".properties.plan1_selector": {
        "value": "Active"
      },
      ".properties.plan1_selector.active.multi_node_deployment": {
        "value": $plan1_multi_node_deployment
      },
      ".properties.plan1_selector.active.name": {
        "value": $plan1_name
      },
      ".properties.plan1_selector.active.description": {
        "value": $plan1_description
      },
      ".properties.plan1_selector.active.instance_limit": {
        "value": $plan1_instance_limit
      },
      ".properties.plan1_selector.active.vm_type": {
        "value": $plan1_vm_type
      },
      ".properties.plan1_selector.active.disk_size": {
        "value": $plan1_disk_size
      },
      ".properties.plan1_selector.active.az_multi_select": {
        "value": $($other_azs | split(","))
      },
      ".properties.plan1_selector.active.access_dropdown": {
        "value": $plan1_access
      }
    }

    +

    if $has_plan2_enabled == "enabled" then
    {
       ".properties.plan2_selector": {
          "value": "Active"
        },
        ".properties.plan2_selector.active.multi_node_deployment": {
          "value": $plan2_multi_node_deployment
        },
        ".properties.plan2_selector.active.name": {
          "value": $plan2_name
        },
        ".properties.plan2_selector.active.description": {
          "value": $plan2_description
        },
        ".properties.plan2_selector.active.instance_limit": {
          "value": $plan2_instance_limit
        },
        ".properties.plan2_selector.active.vm_type": {
          "value": $plan2_vm_type
        },
        ".properties.plan2_selector.active.disk_size": {
          "value": $plan2_disk_size
        },
        ".properties.plan2_selector.active.az_multi_select": {
          "value": $($other_azs | split(","))
        },
        ".properties.plan2_selector.active.access_dropdown": {
          "value": $plan2_access
        }
    }
    else
    {
     ".properties.plan2_selector": {
        "value": "Inactive"
      }
    }
    end

    +

    if $has_plan3_enabled == "enabled" then
    {
       ".properties.plan3_selector": {
          "value": "Active"
        },
        ".properties.plan3_selector.active.multi_node_deployment": {
          "value": $plan3_multi_node_deployment
        },
        ".properties.plan3_selector.active.name": {
          "value": $plan3_name
        },
        ".properties.plan3_selector.active.description": {
          "value": $plan3_description
        },
        ".properties.plan3_selector.active.instance_limit": {
          "value": $plan3_instance_limit
        },
        ".properties.plan3_selector.active.vm_type": {
          "value": $plan3_vm_type
        },
        ".properties.plan3_selector.active.disk_size": {
          "value": $plan3_disk_size
        },
        ".properties.plan3_selector.active.az_multi_select": {
          "value": $($other_azs | split(","))
        },
        ".properties.plan3_selector.active.access_dropdown": {
          "value": $plan3_access
        }
    }
    else
    {
     ".properties.plan3_selector": {
        "value": "Inactive"
      }
    }
    end

    +

    if $has_plan4_enabled == "enabled" then
    {
       ".properties.plan4_selector": {
          "value": "Active"
        },
        ".properties.plan4_selector.active.multi_node_deployment": {
          "value": $plan4_multi_node_deployment
        },
        ".properties.plan4_selector.active.name": {
          "value": $plan4_name
        },
        ".properties.plan4_selector.active.description": {
          "value": $plan4_description
        },
        ".properties.plan4_selector.active.instance_limit": {
          "value": $plan4_instance_limit
        },
        ".properties.plan4_selector.active.vm_type": {
          "value": $plan4_vm_type
        },
        ".properties.plan4_selector.active.disk_size": {
          "value": $plan4_disk_size
        },
        ".properties.plan4_selector.active.az_multi_select": {
          "value": $($other_azs | split(","))
        },
        ".properties.plan4_selector.active.access_dropdown": {
          "value": $plan4_access
        }
    }
    else
    {
     ".properties.plan4_selector": {
        "value": "Inactive"
      }
    }
    end

    +

    if $has_plan5_enabled == "enabled" then
    {
       ".properties.plan5_selector": {
          "value": "Active"
        },
        ".properties.plan5_selector.active.multi_node_deployment": {
          "value": $plan5_multi_node_deployment
        },
        ".properties.plan5_selector.active.name": {
          "value": $plan5_name
        },
        ".properties.plan5_selector.active.description": {
          "value": $plan5_description
        },
        ".properties.plan5_selector.active.instance_limit": {
          "value": $plan5_instance_limit
        },
        ".properties.plan5_selector.active.vm_type": {
          "value": $plan5_vm_type
        },
        ".properties.plan5_selector.active.disk_size": {
          "value": $plan5_disk_size
        },
        ".properties.plan5_selector.active.az_multi_select": {
          "value": $($other_azs | split(","))
        },
        ".properties.plan5_selector.active.access_dropdown": {
          "value": $plan5_access
        }
    }
    else
    {
     ".properties.plan5_selector": {
        "value": "Inactive"
      }
    }
    end

    +

    if $enabled_backup == "s3" then
    {
      ".properties.backups_selector": {
        "value": "S3 backups"
      },
      ".properties.backups_selector.s3.access_key_id": {
        "value": $TILE_MYSQLV2_S3_ACCESS_KEY
      },
      ".properties.backups_selector.s3.secret_access_key": {
        "value": $plan5_name
      },
      ".properties.backups_selector.s3.endpoint_url": {
        "value": $plan5_description
      },
      ".properties.backups_selector.s3.bucket_name": {
        "value": $plan5_instance_limit
      },
      ".properties.backups_selector.s3.path": {
        "value": $plan5_vm_type
      },
      ".properties.backups_selector.s3.cron_schedule": {
        "value": $backup_cron_schedule
      },
      ".properties.backups_selector.s3.enable_email_alerts": {
        "value": $backup_email_alerts
      },
      ".properties.backups_selector.s3.region": {
        "value": $plan5_access
      }
    }
    elif $enabled_backup == "azure" then
    {
      ".properties.backups_selector": {
        "value": "GCS"
      },
      ".properties.backups_selector.azure.account": {
        "value": $
      },
      ".properties.backups_selector.azure.storage_access_key": {
        "value": $
      },
      ".properties.backups_selector.azure.path": {
        "value": $
      },
      ".properties.backups_selector.azure.container": {
        "value": $
      },
      ".properties.backups_selector.azure.blob_store_base_url": {
        "value": $
      },
      ".properties.backups_selector.azure.cron_schedule": {
        "value": $backup_cron_schedule
      },
      ".properties.backups_selector.azure.enable_email_alerts": {
        "value": $backup_email_alerts
      }
    }
    elif $enabled_backup == "scp" then
    {
      ".properties.backups_selector": {
        "value": "SCP backups"
      },
      ".properties.backups_selector.scp.user": {
        "value": $
      },
      ".properties.backups_selector.scp.server": {
        "value": $
      },
      ".properties.backups_selector.scp.destination": {
        "value": $
      },
      ".properties.backups_selector.scp.fingerprint": {
        "value": $
      },
      ".properties.backups_selector.scp.key": {
        "value": $
      },
      ".properties.backups_selector.scp.port": {
        "value": $
      },
      ".properties.backups_selector.scp.cron_schedule": {
        "value": $backup_cron_schedule
      },
      ".properties.backups_selector.scp.enable_email_alerts": {
        "value": $backup_email_alerts
      }
    }
    elif $enabled_backup == "azure" then
    {
      ".properties.backups_selector": {
        "value": "GCS"
      },
      ".properties.backups_selector.gcs.project_id": {
        "value": $
      },
      ".properties.backups_selector.gcs.bucket_name": {
        "value": $
      },
      ".properties.backups_selector.gcs.service_account_json": {
        "value": $
      },
      ".properties.backups_selector.gcs.cron_schedule": {
        "value": $backup_cron_schedule
      },
      ".properties.backups_selector.gcs.enable_email_alerts": {
        "value": $backup_email_alerts
      }
    }
    else
    {
      ".properties.backups_selector": {
        "value": "No backups"
      }
    }
    end
'
)


RESOURCES=$(cat <<-EOF
{
  "proxy": {
    "instance_type": {"id": "automatic"},
    "instances" : $TILE_MYSQL_PROXY_INSTANCES
  },
  "backup-prepare": {
    "instance_type": {"id": "automatic"},
    "instances" : $TILE_MYSQL_BACKUP_PREPARE_INSTANCES
  },
  "monitoring": {
    "instance_type": {"id": "automatic"},
    "instances" : $TILE_MYSQL_MONITORING_INSTANCES
  },
  "cf-mysql-broker": {
    "instance_type": {"id": "automatic"},
    "instances" : $TILE_MYSQL_BROKER_INSTANCES
  }
}
EOF
)


om \
    -t https://$OPS_MGR_HOST \
    -u $OPS_MGR_USR \
    -p $OPS_MGR_PWD  \
    -k configure-product \
    -n $PRODUCT_NAME \
    -p "$PROPERTIES" \
    -pn "$NETWORK" \
    -pr "$RESOURCES"

# Set Errands to on Demand for 1.10
if [ "$IS_ERRAND_WHEN_CHANGED_ENABLED" == "true" ]; then
  echo "applying errand configuration"
  sleep 6
  MYSQL_ERRANDS=$(cat <<-EOF
{"errands":[
  {"name":"broker-registrar","post_deploy":"when-changed"},
  {"name":"smoke-tests","post_deploy":"when-changed"}]}
EOF
)


om \
    -t https://$OPS_MGR_HOST \
    -u $OPS_MGR_USR \
    -p $OPS_MGR_PWD  \
    -k curl -p "/api/v0/staged/products/$PRODUCT_GUID/errands" \
    -x PUT -d "$MYSQL_ERRANDS"

fi


# if nsx is not enabled, skip remaining steps
if [ "$IS_NSX_ENABLED" == "null" -o "$IS_NSX_ENABLED" == "" ]; then
  exit
fi

# Proceed if NSX is enabled on Bosh Director
# Support NSX LBR Integration


# $MYSQL_TILE_JOBS_REQUIRING_LBR comes filled by nsx-edge-gen list command
# Sample: ERT_TILE_JOBS_REQUIRING_LBR='mysql_proxy,tcp_router,router,diego_brain'
JOBS_REQUIRING_LBR=$MYSQL_TILE_JOBS_REQUIRING_LBR

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
  SECURITY_GROUP=$(env | grep "TILE_MYSQL_${job_name_upper}_SECURITY_GROUP" | awk -F '=' '{print $2}')

  match=$(echo $job_name | grep -e $JOBS_REQUIRING_LBR_PATTERN  || true)
  if [ "$match" != "" -o  "$SECURITY_GROUP" != "" ]; then
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
    LBR_DETAILS=${MYSQL_TILE_JOBS_LBR_MAP[$job_name]}

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

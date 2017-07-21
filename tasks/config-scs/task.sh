#!/bin/bash

set -e

chmod +x om-cli/om-linux

# Check if Bosh Director is v1.11 or higher
export BOSH_PRODUCT_VERSION=$(./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k \
           curl -p "/api/v0/deployed/products" 2>/dev/null | jq '.[] | select(.installation_name=="p-bosh") | .product_version' | tr -d '"')
export BOSH_MAJOR_VERSION=$(echo $BOSH_PRODUCT_VERSION | awk -F '.' '{print $1}' )
export BOSH_MINOR_VERSION=$(echo $BOSH_PRODUCT_VERSION | awk -F '.' '{print $2}' )

export IS_ERRAND_WHEN_CHANGED_ENABLED=false
if [ "$BOSH_MAJOR_VERSION" -le 1 ]; then
  if [ "$BOSH_MINOR_VERSION" -ge 10 ]; then
    export IS_ERRAND_WHEN_CHANGED_ENABLED=true
  fi
else
  export IS_ERRAND_WHEN_CHANGED_ENABLED=true
fi


TILE_RELEASE=`./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k available-products | grep p-spring-cloud-services`

PRODUCT_NAME=`echo $TILE_RELEASE | cut -d"|" -f2 | tr -d " "`
PRODUCT_VERSION=`echo $TILE_RELEASE | cut -d"|" -f3 | tr -d " "`

./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k stage-product -p $PRODUCT_NAME -v $PRODUCT_VERSION

function fn_get_azs {
     local azs_csv=$1
     echo $azs_csv | awk -F "," -v braceopen='{' -v braceclose='}' -v name='"name":' -v quote='"' -v OFS='"},{"name":"' '$1=$1 {print braceopen name quote $0 quote braceclose}'
}

TILE_AVAILABILITY_ZONES=$(fn_get_azs $TILE_AZS_SCS)


NETWORK=$(cat <<-EOF
{
  "singleton_availability_zone": {
    "name": "$TILE_AZ_SCS_SINGLETON"
  },
  "other_availability_zones": [
    $TILE_AVAILABILITY_ZONES
  ],
  "network": {
    "name": "$NETWORK_NAME"
  }
}
EOF
)

PROPERTIES=$(cat <<-EOF
{
  ".deploy-service-broker.broker_max_instances": {
    "value": 100
  },  
  ".deploy-service-broker.disable_cert_check": {
    "value": true
  }
}
EOF
)

./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k configure-product -n $PRODUCT_NAME -p "$PROPERTIES"  -pn "$NETWORK"

PRODUCT_GUID=$(./om-cli/om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
                     curl -p "/api/v0/staged/products" -x GET \
                     | jq '.[] | select(.installation_name | contains("p-spring-cloud-services")) | .guid' | tr -d '"')


# Set Errands to on Demand for 1.10
if [ "$IS_ERRAND_WHEN_CHANGED_ENABLED" == "true" ]; then
  echo "applying errand configuration"
  sleep 6
  SCS_ERRANDS=$(cat <<-EOF
{"errands":[
  {"name":"deploy-service-broker","post_deploy":"when-changed"},
  {"name":"register-service-broker","post_deploy":"when-changed"},
  {"name":"run-smoke-tests","post_deploy":"when-changed"}
  ]
}
EOF
)

  ./om-cli/om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
                              curl -p "/api/v0/staged/products/$PRODUCT_GUID/errands" \
                              -x PUT -d "$SCS_ERRANDS"
fi

#!/bin/bash -eu


export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-ci-pipeline/functions/check_versions.sh
source $ROOT_DIR/nsx-ci-pipeline/functions/upload_stemcell.sh

if [[ -n "$NO_PROXY" ]]; then
  echo "$OM_IP $OPS_MGR_HOST" >> /etc/hosts
fi


STEMCELL_VERSION_FROPS_PRODUCT_METADATA=$(
  cat ./pivnet-product/metadata.json |
  jq --raw-output \
    '
    [
      .Dependencies[]
      | select(.Release.Product.Name | contains("Stemcells"))
      | .Release.Version
    ]
    | map(split(".") | map(tonumber))
    | transpose | transpose
    | max // empty
    | map(tostring)
    | join(".")
    '
)

tile_metadata=$(unzip -l pivnet-product/*.pivotal | grep "metadata" | grep "ml$" | awk '{print $NF}')
STEMCELL_VERSION_FROPS_TILE=$(unzip -p pivnet-product/*.pivotal $tile_metadata | grep -A4 stemcell | grep version: \
                                                      | grep -Ei "[0-9]+{4}" | awk '{print $NF}' | sed "s/'//g" )

upload_stemcells "$STEMCELL_VERSION_FROPS_TILE $STEMCELL_VERSION_FROPS_PRODUCT_METADATA"

# Should the slug contain more than one product, pick only the first.
FILE_PATH=`find ./pivnet-product -name *.pivotal | sort | head -1`
om \
  -t https://$OPS_MGR_HOST \
  -k -u $OPS_MGR_USR \
  -p $OPS_MGR_PWD \
  -k --request-timeout 3600 \
  upload-product -p $FILE_PATH



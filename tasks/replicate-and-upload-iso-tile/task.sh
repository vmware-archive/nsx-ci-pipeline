#!/bin/bash -e

export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-ci-pipeline/functions/check_versions.sh

chmod +x replicator/replicator-linux

export PATH=$PATH:$ROOT_DIR/replicator


INPUT_FILE_PATH=`find ./pivnet-iso-product -name "*.pivotal"`
FILE_NAME=`echo $INPUT_FILE_PATH | cut -d '/' -f3`
OUTPUT_FILE_PATH=replicator-tile/$FILE_NAME

if [[ ! -z "$REPLICATOR_NAME" ]]; then
  echo "Replicating the tile and adding " $REPLICATOR_NAME
  mkdir replicator-tile
  replicator-linux \
    -name $REPLICATOR_NAME \
    -path $INPUT_FILE_PATH \
    -output $OUTPUT_FILE_PATH

  om \
    -t https://$OPS_MGR_HOST \
    -k -u $OPS_MGR_USR \
    -p $OPS_MGR_PWD \
    -k upload-product \
    -p $OUTPUT_FILE_PATH
else
  echo "Uploading tile without any replication"
  FILE_PATH=`find ./pivnet-product -name *.pivotal`
  om \
    -t https://$OPS_MGR_HOST \
    -k -u $OPS_MGR_USR \
    -p $OPS_MGR_PWD \
    -k upload-product \
    -p $FILE_PATH
fi


STEMCELL_VERSION=`cat ./pivnet-iso-product/metadata.json | jq '.Dependencies[] | select(.Release.Product.Name | contains("Stemcells")) | .Release.Version'`
echo "Downloading stemcell $STEMCELL_VERSION for $SERVICE_STRING product"

pivnet-cli login --api-token="$PIVNET_API_TOKEN"
pivnet-cli download-product-files -p stemcells -r $STEMCELL_VERSION -g "*vsphere*" --accept-eula

SC_FILE_PATH=`find ./ -name *.tgz`

om \
  -t https://$OPS_MGR_HOST \
  --skip-ssl-validation \
  -u $OPS_MGR_USR \
  -p $OPS_MGR_PWD \
  -k upload-stemcell \
  -s $SC_FILE_PATH

if [ ! -f "$SC_FILE_PATH" ]; then
    echo "Stemcell file not found!"
else
  echo "Removing downloaded stemcell $STEMCELL_VERSION"
  rm $SC_FILE_PATH
fi

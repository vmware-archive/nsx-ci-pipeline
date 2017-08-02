#!/bin/bash -ex

PIVNET_CLI=`find ./pivnet-cli -name "*linux-amd64*"`

chmod +x replicator/replicator-linux
chmod +x $PIVNET_CLI
chmod +x om-cli/om-linux

CMD=./replicator/replicator-linux

INPUT_FILE_PATH=`find ./pivnet-iso-product -name "*.pivotal"`
FILE_NAME=`echo $INPUT_FILE_PATH | cut -d '/' -f3`
OUTPUT_FILE_PATH=replicator-tile/$FILE_NAME

chmod +x om-cli/om-linux
OM_CMD=./om-cli/om-linux

if [[ ! -z "$REPLICATOR_NAME" ]]; then
  echo "Replicating the tile and adding " $REPLICATOR_NAME
  mkdir replicator-tile
  $CMD -name $REPLICATOR_NAME -path $INPUT_FILE_PATH -output $OUTPUT_FILE_PATH
  $OM_CMD -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k upload-product -p $OUTPUT_FILE_PATH
else
  echo "Uploading tile without any replication"
  FILE_PATH=`find ./pivnet-product -name *.pivotal`
  $OM_CMD -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k upload-product -p $FILE_PATH
fi


STEMCELL_VERSION=`cat ./pivnet-iso-product/metadata.json | jq '.Dependencies[] | select(.Release.Product.Name | contains("Stemcells")) | .Release.Version'`
echo "Downloading stemcell $STEMCELL_VERSION for $SERVICE_STRING product"

$PIVNET_CLI login --api-token="$PIVNET_API_TOKEN"
$PIVNET_CLI download-product-files -p stemcells -r $STEMCELL_VERSION -g "*vsphere*" --accept-eula

SC_FILE_PATH=`find ./ -name *.tgz`

./om-cli/om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k upload-stemcell -s $SC_FILE_PATH

if [ ! -f "$SC_FILE_PATH" ]; then
    echo "Stemcell file not found!"
else
  echo "Removing downloaded stemcell $STEMCELL_VERSION"
  rm $SC_FILE_PATH
fi

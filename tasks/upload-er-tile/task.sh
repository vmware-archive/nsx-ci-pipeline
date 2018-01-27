#!/bin/bash

PIVNET_CLI=`find ./pivnet-cli -name "*linux-amd64*"`
chmod +x $PIVNET_CLI

chmod +x om-cli/om-linux
export ROOT_DIR=`pwd`
export PATH=$PATH:$ROOT_DIR/om-cli
source $ROOT_DIR/concourse-vsphere/functions/check_versions.sh


if [ "$USE_SRT_TILE" == "true" ]; then
  FILE_PATH=`find ./pivnet-er-product -name srt*.pivotal`
else
  FILE_PATH=`find ./pivnet-er-product -name cf*.pivotal`
fi

STEMCELL_VERSION=`cat ./pivnet-er-product/metadata.json | jq '.Dependencies[] | select(.Release.Product.Name | contains("Stemcells")) | .Release.Version'`

echo "Downloading stemcell $STEMCELL_VERSION"
$PIVNET_CLI login --api-token="$PIVNET_API_TOKEN"

./$PIVNET_CLI download-product-files -p stemcells -r $STEMCELL_VERSION -g "*vsphere*" --accept-eula

SC_FILE_PATH=`find ./ -name *.tgz`

om-linux \
	-t https://$OPS_MGR_HOST \
	-k -u $OPS_MGR_USR \
	-p $OPS_MGR_PWD \
	-k upload-product \
	-p $FILE_PATH

om-linux \
	-t https://$OPS_MGR_HOST \
	-k -u $OPS_MGR_USR \
	-p $OPS_MGR_PWD \
	-k upload-stemcell \
	-s $SC_FILE_PATH

if [ ! -f "$SC_FILE_PATH" ]; then
    echo "Stemcell file not found!"
else
  echo "Removing downloaded stemcell $STEMCELL_VERSION"
  rm $SC_FILE_PATH
fi

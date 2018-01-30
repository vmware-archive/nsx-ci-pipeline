#!/bin/bash -e

export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-ci-pipeline/functions/check_versions.sh


until $(curl --output /dev/null -k --silent --head --fail https://$OPS_MGR_HOST/setup); do
    printf '.'
    sleep 5
done

om \
	-t https://$OPS_MGR_HOST \
	-k configure-authentication \
	-u $OPS_MGR_USR \
	-p $OPS_MGR_PWD \
	-dp $OM_DECRYPTION_PWD

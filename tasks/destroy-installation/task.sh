#!/bin/bash

export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-ci-pipeline/functions/copy_binaries.sh

# Check for pending changes before starting deletion
pending_changes=$( om \
	-f json \
	-t https://$OPS_MGR_HOST \
	-k -u $OPS_MGR_USR \
	-p $OPS_MGR_PWD \
	pending-changes
	)
# If there are any pending changes, then revert them before starting deletion
if [ "$pending_changes" != '[]' ]; then
	om  \
		-f json \
		-t https://$OPS_MGR_HOST \
		-k -u $OPS_MGR_USR \
		-p $OPS_MGR_PWD \
		revert-staged-changes
fi

om \
	-t https://$OPS_MGR_HOST \
	-k -u $OPS_MGR_USR \
	-p $OPS_MGR_PWD \
	delete-installation \
|| om \
	-t https://$OPS_MGR_HOST \
	-k -u $OPS_MGR_USR \
	-p $OPS_MGR_PWD \
	delete-installation

STATUS=$?
exit $STATUS

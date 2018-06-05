#!/bin/bash


export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_versions.sh
source $ROOT_DIR/nsx-ci-pipeline/functions/check_null_variables.sh

check_available_product_version "cf"

enabled_errands=$(
  om-linux \
    --target "https://${OPS_MGR_HOST}" \
    --skip-ssl-validation \
    --username $OPS_MGR_USR \
    --password $OPS_MGR_PWD \
    errands \
    --product-name "$PRODUCT_NAME" |
  tail -n+4 | head -n-1 | grep -v false | cut -d'|' -f2 | tr -d ' '
)

errands_to_run_on_change="${enabled_errands[@]}"

will_run_on_change=$(
  echo $enabled_errands |
  jq \
    --arg run_on_change "${errands_to_run_on_change[@]}" \
    --raw-input \
    --raw-output \
    'split(" ")
    | reduce .[] as $errand ([];
       if $run_on_change | contains($errand) then
         . + [$errand]
       else
         .
       end)
    | join("\n")'
)

if [ -z "$will_run_on_change" ]; then
  echo Nothing to do.
  exit 0
fi

while read errand; do
  echo -n Set $errand to run on change...
  om-linux \
    --target "https://${OPS_MGR_HOST}" \
    --skip-ssl-validation \
    --username "$OPS_MGR_USR" \
    --password "$OPS_MGR_PWD" \
    set-errand-state \
    --product-name "$PRODUCT_NAME" \
    --errand-name $errand \
    --post-deploy-state "when-changed"
  echo done
done < <(echo "$will_run_on_change")

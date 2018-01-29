function generate_cert () (
  set -eu
  local domains="$1"

  local data=$(echo $domains | jq --raw-input -c '{"domains": (. | split(" "))}')

  local response=$(
    om \
      -t "https://${OPS_MGR_HOST}" \
      -u "$OPS_MGR_USR" \
      -p "$OPS_MGR_PWD" \
      --skip-ssl-validation \
      curl \
      --silent \
      --path "/api/v0/certificates/generate" \
      -x POST \
      -d $data
    )

  echo "$response"
)

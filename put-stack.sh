#!/usr/bin/env bash

set -euxo pipefail

export STACK_NAME="${1:?Usage: $0 <stack name>}"

CONFIGPATH="secret.json"
if [ ! -r "$CONFIGPATH" ] ; then
  echo "Error: Config json at $CONFIGPATH does not exist"
  exit 1
fi

if aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" > /dev/null 2> /dev/null ; then
  CMD=update
else
  CMD=create
fi

IPADDR="$(aws cloudformation describe-stacks --stack-name mattermost --query 'Stacks[0].Outputs[0].OutputValue' --output text)"
./ssh-command "$IPADDR" 'sudo systemctl stop mattermost'
./ssh-command "$IPADDR" 'sudo systemctl start backup-mattermost'

aws cloudformation "$CMD-stack" \
  --output text \
  --stack-name "$STACK_NAME" \
  --template-body file://cfn.json \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --parameters "$(cat "$CONFIGPATH")" > /dev/null

STATUS="UPDATE_IN_PROGRESS"
while [ "$STATUS" == "UPDATE_IN_PROGRESS" ]; do
  echo "Waiting for stack to update... $STATUS"
  sleep 10
  STATUS="$(aws cloudformation describe-stacks --stack-name="$STACK_NAME" | jq -r .Stacks[].StackStatus)"
done

IPADDR="$(aws cloudformation describe-stacks --stack-name mattermost --query 'Stacks[0].Outputs[0].OutputValue' --output text)"

# Calls the cloudflare API with a hard-coded token
function cfapi
{
  local endpoint=${1:?Usage: cfapi <endpoint>}
  shift
  curl \
  -H "Authorization: Bearer $(cat cloudflare_api_key)" \
  -H "Content-Type:application/json" \
  "https://api.cloudflare.com/client/v4/zones/$(cat cloudflare_zone)/${endpoint}" \
  "$@"
}


  CURLDATA="$(cat <<-JSON
    {
      "type": "A",
      "name": "@",
      "content": "$IPADDR",
      "ttl": 60,
      "proxied": false
  }
JSON
  )"

  # Destroy existing DNS records
  for record in $( cfapi "dns_records" | jq -r ".result[] | select(.type == \"A\").id" ) ; do
    cfapi "dns_records/$record" -X DELETE
  done

  # Create DNS record
  cfapi "dns_records" \
    --data "$CURLDATA" \
    | jq .

sleep 60 # Wait for SSH to come up

./ssh-command "$IPADDR" 'sudo systemctl start restore-mattermost'

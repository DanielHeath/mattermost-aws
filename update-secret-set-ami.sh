#!/bin/bash
IMAGE_ID="$(jq -r ".builds[-1].artifact_id" < "packer-manifest.json" | sed s/.*://)"

tmp=$(mktemp)

jq --arg ami "$IMAGE_ID" 'map((select(.ParameterKey == "ImageId") | .ParameterValue) = $ami)' secret.json > "$tmp" && mv "$tmp" secret.json

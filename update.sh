#!/bin/bash
set -euxo pipefail

./in-aws-profile packer build -var region=ap-southeast-4 instance.pkr.hcl
./update-secret-set-ami.sh
./in-aws-profile ./put-stack.sh mattermost
ssh-keygen -f "/home/daniel/.ssh/known_hosts" -R "nerdy.party"

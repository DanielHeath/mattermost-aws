#!/bin/bash
set -euxo pipefail

./in-aws-profile packer build -var region=ap-southeast-4 instance.pkr.hcl
./update-secret-set-ami.sh
./aws-profile ./put-stack.sh mattermost

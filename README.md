# Cloudformation stack for mattermost

This repository contains scripts to run your own mattermost instance on a domain you own.

It runs a single ec2 node (very cheap; $50USD for 3 years if you buy an EC2 Instance Savings Plan), with hourly backups to s3 (with versioning enabled, to prevent good backups being overwritten with bad). Old versions are expired after 60 days.

## Status

At the time of writing (nov 2023) it's working for me.

## Dependencies

AWS account
Cloudflare for DNS

## Wrinkles

Downtime during upgrades - because the database is hosted on the sole instance, you need to shut down the old instance (and backup its database) before starting a new one

## How to use

Install dependencies: `packer`, `aws` and `jq`.
Create a file named `cloudflare_zone` contains the cloudflare zone ID for your instance
Create a file named `cloudflare_api_key` contains a cloudflare API key that can set DNS for that zone
`cp secret.json.sample secret.json` and fill out your own settings (setup SES for your domain to get SMTP credentials)
Edit `ssh-command` to use your key
Edit `aws-profile` to specify your AWS credentials
Run `./update.sh`

#!/bin/sh
set -e

ssh-keygen -f generated/ssh/openvpn_ssh_key -t rsa -b 4096 -q -N ""

if [ ! -f "backend.tfvars" ]; then echo "Missing terraform backend config file"; fi
terraform init -backend-config=backend.tfvars

if [ ! -f "aws_shared_credentials" ]; then echo "Missing terraform aws credentials file"; fi
AWS_SHARED_CREDENTIALS_FILE=aws_shared_credentials terraform apply -auto-approve

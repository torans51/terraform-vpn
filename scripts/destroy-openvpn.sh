#!/bin/sh
set -e

AWS_SHARED_CREDENTIALS_FILE=aws_shared_credentials terraform destroy -auto-approve

rm -rf generated/ssh/*
rm -rf generated/openvpn-conf/*

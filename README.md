# OpenVPN terraform configuration

This repo will create an EC2 instance on AWS with OpenVPN.

## Setup
In order to create and execute the terraform scripts you need to create 2 file:
* `aws_shared_credentials`
* `terraform.tfvars`
* `backend.tfvars`

For `aws_shared_credentials` file copy the template `aws_shared_credentials.example` and fill access key and secret access key with the credentials of user with admin privileges.

To get this information you need to create a user in IAM section in the AWS dashboad with admin permissions (see amazon doc https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_create.html).

For `terraform.tfvars` file copy the template `terraform.tfvars.example` and setup the aws region and the project name to use.

For `backend.tfvars` file copy the template `backend.tfvars.example` and fill the values with s3 bucket and dynamodb table that will contain terraform state and terraform state lock (see this other repository to configure S3 and DynamoDB).

## Create the OpenVPN

To create all the infrastructure you just need to execute the following command from the root folder of the project

```
./scripts/create-openvpn.sh
```

This script will do the following action:
* create an ssh key pair to login to the EC2 instance in `generated/ssh`
* init terraform using the S3 backend config
* create the AWS infrastructure
* setup the OpenPVN on the EC2 instance
* create a user with name `test`
* download the openvpn conf file in `generated/openvpn-conf`

To access the VPN you can use the file 

```
generated/openvpn-conf/test.ovpn
```

in a OpenVPN GUI or from command line

```
sudo openvpn generated/openvpn-conf/test.ovpn
```

Notice that `sudo` is required

## Destroy the OpenVPN

To destroy the infrastructure on AWS you just need to run the following script

```
./scripts/destroy-openvpn.sh
```

This script will also remove the file created by the `create-opencpn.sh` script inside the `generated folder`

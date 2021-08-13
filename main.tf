// Define variables
variable aws_region {
  description = "The AWS region to use"
}

variable project_name {
  description = "The project name to use"
}

locals {
  tag_provisioner = "Terraform"
  ssh_folder = "${path.module}/generated/ssh"
  ssh_key_name = "openvpn_ssh_key"
  openvpn_conf_folder = "${path.module}/generated/openvpn-conf"
  vpc_cidr_block = "10.0.0.0/16"
  ec2_instance_type = "t2.micro"
  ec2_username = "ec2-user"
  ssh_private_key_path = "${local.ssh_folder}/${local.ssh_key_name}"
  ssh_public_key_path = "${local.ssh_folder}/${local.ssh_key_name}.pub"
}

// Define provider
terraform {
  required_version = "1.0.3"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 3.51.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Name = var.project_name
      Provisioner = local.tag_provisioner
    }
  }
}

// Define VPC
resource "aws_vpc" "openvpn_vpc" {
  cidr_block = local.vpc_cidr_block
  enable_dns_hostnames = true 
  enable_dns_support = true
}

resource "aws_subnet" "openvpn_sn" {
  vpc_id = aws_vpc.openvpn_vpc.id
  cidr_block = cidrsubnet(local.vpc_cidr_block, 8, 0)
}

resource "aws_internet_gateway" "openvpn_igw" {
  vpc_id = aws_vpc.openvpn_vpc.id
}

resource "aws_route_table" "openvpn_rt" {
  vpc_id = aws_vpc.openvpn_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.openvpn_igw.id
  }
}

resource "aws_route_table_association" "openvpn_rta" {
  subnet_id = aws_subnet.openvpn_sn.id
  route_table_id = aws_route_table.openvpn_rt.id
}

resource "aws_security_group" "openvpn_sg_udp" {
  name = "${var.project_name}-sg-udp"
  description = "Allow inboud UDP acces to OpenVPN and unristricted egress"

  vpc_id = aws_vpc.openvpn_vpc.id

  ingress {
    from_port = 1194
    to_port = 1194
    protocol = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "openvpn_sg_ssh" {
  name = "${var.project_name}-ssh"
  description = "Allow ssh access from anywhere"

  vpc_id = aws_vpc.openvpn_vpc.id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// Ec2 instance
data "aws_ami" "openvpn_ami" {
  most_recent = true

  filter {
    name = "name"
    values = ["amzn2-ami-hvm*"]
  }

  filter {
    name = "architecture"
    values = ["x86_64"]
  }

  filter {
    name = "block-device-mapping.volume-type"
    values = ["gp2"]
  }

  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

resource "aws_key_pair" "openvpn_ssh_kp" {
  key_name = local.ssh_key_name
  public_key = file("${local.ssh_public_key_path}")
}

resource "aws_instance" "openvpn_instance" {
  ami = data.aws_ami.openvpn_ami.id
  instance_type = local.ec2_instance_type
  associate_public_ip_address = true
  key_name = aws_key_pair.openvpn_ssh_kp.key_name
  subnet_id = aws_subnet.openvpn_sn.id

  vpc_security_group_ids = [
    aws_security_group.openvpn_sg_udp.id,
    aws_security_group.openvpn_sg_ssh.id
  ]

  root_block_device {
    volume_type = "gp2"
    volume_size = 8 // The size of the root block device volume of the EC2 instance in GiB
    delete_on_termination = true
  }
}

resource "null_resource" "openvpn_boostrap" {
  depends_on = [aws_instance.openvpn_instance]
  
  connection {
    type = "ssh"
    host = aws_instance.openvpn_instance.public_ip
    user = local.ec2_username
    port = "22"
    private_key = file("${local.ssh_private_key_path}")
    agent = false
  }
  
  provisioner "remote-exec" {
    inline = [
      "curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh",
      "chmod +x openvpn-install.sh",
      "sudo AUTO_INSTALL=y APPROVE_IP=y ./openvpn-install.sh"
    ]
  }
} 
   
resource "null_resource" "openvpn_create_user" {
  depends_on = [null_resource.openvpn_boostrap]
     
  connection {
    type = "ssh"
    host = aws_instance.openvpn_instance.public_ip
    user = local.ec2_username
    port = "22"
    private_key = file("${local.ssh_private_key_path}")
    agent = false
  }  
     
  provisioner "remote-exec" {
    inline = [
      "sudo MENU_OPTION=\"1\" CLIENT=\"test\" PASS=1 ./openvpn-install.sh"
    ]
  }
}

resource "null_resource" "openvpn_download_conf" {
  depends_on = [null_resource.openvpn_create_user]

  connection {
    type = "ssh"
    host = aws_instance.openvpn_instance.public_ip
    user = local.ec2_username
    port = "22"
    private_key = file("${local.ssh_private_key_path}")
    agent = false
  }

  provisioner "local-exec" {
    command = <<EOT
      scp -i ${local.ssh_private_key_path} \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        ${local.ec2_username}@${aws_instance.openvpn_instance.public_ip}:'/home/${local.ec2_username}/*.ovpn' generated/openvpn-conf
    EOT
  }
}

output "ec2_instance_dns" {
  value = aws_instance.openvpn_instance.public_dns
}

output "ec2_instance_ip" {
  value = aws_instance.openvpn_instance.public_ip
}

output "ec2_instance_ssh" {
  value = "ssh -i ${local.ec2_username}@${aws_instance.openvpn_instance.public_ip}"
}

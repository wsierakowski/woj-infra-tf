provider "aws" {
  region = "eu-central-1"
}

data "aws_caller_identity" "my_account" {}

resource "aws_vpc" "sigman_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "sigmanVPC"
  }
}

###################
# Public Subnets
###################

resource "aws_subnet" "sigman_public_1" {
  cidr_block = "10.0.1.0/24"
  vpc_id = aws_vpc.sigman_vpc.id
  availability_zone = "eu-central-1a"

  tags = {
    Name = "sigmanPublic1"
  }
}

resource "aws_subnet" "sigman_public_2" {
  cidr_block = "10.0.2.0/24"
  vpc_id = aws_vpc.sigman_vpc.id
  availability_zone = "eu-central-1b"

  tags = {
    Name = "sigmanPublic2"
  }
}

resource "aws_internet_gateway" "sigman_igw" {
  vpc_id = aws_vpc.sigman_vpc.id

  tags = {
    Name = "sigmanIGW"
  }
}

resource "aws_route_table" "sigman_public_rt" {
  vpc_id = aws_vpc.sigman_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sigman_igw.id
  }

  tags = {
    Name = "sigmanPublicRT"
  }
}

resource "aws_route_table_association" "rta_public_1" {
  route_table_id = aws_route_table.sigman_public_rt.id
  subnet_id = aws_subnet.sigman_public_1.id
}

resource "aws_route_table_association" "rta_public_2" {
  route_table_id = aws_route_table.sigman_public_rt.id
  subnet_id = aws_subnet.sigman_public_1.id
}

###################
# NATandBastion
###################

# SG
resource "aws_security_group" "natAndBastionInstanceSG" {
  name = "nat_bastion"
  description = "SG for NATandBastionInstance"
  vpc_id = aws_vpc.sigman_vpc.id

  # HTTPS only from VPC
  ingress {
    from_port = 443
    protocol = "tcp"
    to_port = 443
    cidr_blocks = ["10.0.0.0/16"]
  }

  # HTTP only from VPC
  ingress {
    from_port = 80
    protocol = "tcp"
    to_port = 80
    cidr_blocks = ["10.0.0.0/16"]
  }

  # PING only from VPC
  ingress {
    from_port = 80
    protocol = "icmp"
    to_port = 80
    cidr_blocks = ["10.0.0.0/16"]
  }

  # SSH from anywhere (VPC and internet)
  ingress {
    from_port = 22
    protocol = "tcp"
    to_port = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ephemeral ports (for requests initiated from VPC)
  ingress {
    from_port = 1024
    protocol = "tcp"
    to_port = 65535
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all traffic out
  egress {
    from_port = 0
    protocol = "tcp"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# EC2 instance
resource "aws_instance" "natAndBastionInstance" {
  ami = "ami-08b9633fe44dfcba1"
  instance_type = "t3.nano"
  subnet_id = aws_subnet.sigman_public_1.id
  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.natAndBastionInstanceSG.id
  ]

  depends_on = [aws_security_group.natAndBastionInstanceSG]
}

output natAndBastionInstancePubIp {
  value = aws_instance.natAndBastionInstance.public_ip
}

###################
# Private Subnets
###################

resource "aws_subnet" "sigman_private_1" {
  cidr_block = "10.0.3.0/24"
  vpc_id = aws_vpc.sigman_vpc.id
  availability_zone = "eu-central-1a"

  tags = {
    Name = "sigmanPrivate1"
  }
}

resource "aws_subnet" "sigman_private_2" {
  cidr_block = "10.0.4.0/24"
  vpc_id = aws_vpc.sigman_vpc.id
  availability_zone = "eu-central-1b"

  tags = {
    Name = "sigmanPrivate2"
  }
}

resource "aws_route_table" "sigman_private_rt" {
  vpc_id = aws_vpc.sigman_vpc.id

//  route {
//    cidr_block = "0.0.0.0/0"
//    nat_gateway_id = ""
//    gateway_id = aws_internet_gateway.sigman_igw.id
//  }

  tags = {
    Name = "sigmanPrivateRT"
  }
}

resource "aws_route_table_association" "rta_private_1" {
  route_table_id = aws_route_table.sigman_private_rt.id
  subnet_id = aws_subnet.sigman_private_1.id
}

resource "aws_route_table_association" "rta_private_2" {
  route_table_id = aws_route_table.sigman_private_rt.id
  subnet_id = aws_subnet.sigman_private_2.id
}

###################
# Private Subnet Instance
###################

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners = ["amazon"]

  filter {
    name = "name"
    values = [
      "amzn2-ami-hvm-*-x86_64-gp2"]
  }

//  filter {
//    name   = "virtualization-type"
//    values = ["hvm"]
//  }
}

# EC2 instance
resource "aws_instance" "privateInstance" {
  ami = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.nano"
  subnet_id = aws_subnet.sigman_private_1.id

//  vpc_security_group_ids = [
//    aws_security_group.natAndBastionInstanceSG.id
//  ]

//  depends_on = [aws_security_group.natAndBastionInstanceSG]
}

output privateInstanceIp {
  value = aws_instance.privateInstance.private_ip
}

/*
terraform state list
*/
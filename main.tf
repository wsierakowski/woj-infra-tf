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

resource "aws_route_table_association" "sigman_vpc_to_public_1" {
  route_table_id = aws_route_table.sigman_public_rt.id
  subnet_id = aws_subnet.sigman_public_1.id
}

resource "aws_route_table_association" "sigman_vpc_to_public_2" {
  route_table_id = aws_route_table.sigman_public_rt.id
  subnet_id = aws_subnet.sigman_public_1.id
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

resource "aws_route_table_association" "sigman_vpc_to_private_1" {
  route_table_id = aws_route_table.sigman_private_rt.id
  subnet_id = aws_subnet.sigman_private_1.id
}

resource "aws_route_table_association" "sigman_vpc_to_private_2" {
  route_table_id = aws_route_table.sigman_private_rt.id
  subnet_id = aws_subnet.sigman_private_1.id
}
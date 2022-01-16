resource "aws_vpc" "sigman" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "sigman"
  }
}

###################
# Public Subnets
###################

resource "aws_subnet" "sigman_public_1" {
  cidr_block = "10.0.1.0/24"
  vpc_id = aws_vpc.sigman.id
  availability_zone = "eu-central-1a"

  tags = {
    Name = "sigman-public-1"
  }
}

resource "aws_subnet" "sigman_public_2" {
  cidr_block = "10.0.2.0/24"
  vpc_id = aws_vpc.sigman.id
  availability_zone = "eu-central-1b"

  tags = {
    Name = "sigman-public-2"
  }
}

resource "aws_internet_gateway" "sigman" {
  vpc_id = aws_vpc.sigman.id

  tags = {
    Name = "sigman-igw"
  }
}

resource "aws_route_table" "sigman_public" {
  vpc_id = aws_vpc.sigman.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sigman.id
  }

  tags = {
    Name = "sigman-public"
  }
}

resource "aws_route_table_association" "public_1" {
  route_table_id = aws_route_table.sigman_public.id
  subnet_id = aws_subnet.sigman_public_1.id
}

resource "aws_route_table_association" "public_2" {
  route_table_id = aws_route_table.sigman_public.id
  subnet_id = aws_subnet.sigman_public_2.id
}

###################
# NATandBastion
###################

# SG
resource "aws_security_group" "nat-and-bastion-instance" {
  name = "nat_bastion"
  description = "SG for NATandBastionInstance"
  vpc_id = aws_vpc.sigman.id

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
    from_port = -1
    protocol = "icmp"
    to_port = -1
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
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# EC2 instance
resource "aws_instance" "nat_and_bastion-instance" {
  ami = "ami-08b9633fe44dfcba1"
  instance_type = "t3.nano"
  subnet_id = aws_subnet.sigman_public_1.id
  associate_public_ip_address = true
  key_name = aws_key_pair.sigman.key_name

  vpc_security_group_ids = [
    aws_security_group.nat-and-bastion-instance.id
  ]
  depends_on = [aws_security_group.nat-and-bastion-instance]

  # User-data script to enable NAT capabilities
  #    wrapped into cloud-config to allow running on every instance run (restarts)
  #    rather than just the initial launch
  # More info: https://aws.amazon.com/premiumsupport/knowledge-center/execute-user-data-ec2/

  user_data = <<EOF
Content-Type: multipart/mixed; boundary="//"
MIME-Version: 1.0

--//
Content-Type: text/cloud-config; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="cloud-config.txt"

#cloud-config
cloud_final_modules:
- [scripts-user, always]

--//
Content-Type: text/x-shellscript; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="userdata.txt"

#!/bin/bash -xe
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
  sysctl -w net.ipv4.ip_forward=1
  /sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
--//--
  EOF

  # Required for NAT
  source_dest_check = false

  tags = {
    Name = "nat-and-bastion"
  }
}

output nat_and_bastion_instance_pub_ip {
  value = aws_instance.nat_and_bastion-instance.public_ip
  description = "NAT-and-Bastion-Instance public ip"
}

output nat_and_bastion_instance_private_ip {
  value = aws_instance.nat_and_bastion-instance.private_ip
  description = "NAT-and-Bastion-Instance private ip"
}

## EC2 Spot instance
#resource "aws_spot_instance_request" "natAndBastionInstance" {
#  ami = "ami-08b9633fe44dfcba1"
#  instance_type = "t3.nano"
#  subnet_id = aws_subnet.sigman_public_1.id
#  associate_public_ip_address = true
#  key_name = aws_key_pair.sigman_key.key_name
#
#  spot_price = "0.006"
#  spot_type = "one-time"
#  # Terraform will wait for the Spot Request to be fulfilled, and will throw
#  # an error if the timeout of 10m is reached.
#  wait_for_fulfillment = true
#
#  vpc_security_group_ids = [
#    aws_security_group.natAndBastionInstanceSG.id
#  ]
#  depends_on = [aws_security_group.natAndBastionInstanceSG]
#
#  # 1. User-data script to enable NAT capabilities
#  #    wrapped into cloud-config to allow running on every instance run
#  #    rather than just the initial launch
#  # 2. TF doesn't support setting source_dest_check on spot instances
#  #    https://github.com/hashicorp/terraform-provider-aws/issues/2751
#  #    Workaround: https://github.com/pulumi/pulumi-aws/issues/959
#  user_data = <<EOF
#    Content-Type: multipart/mixed; boundary="//"
#    MIME-Version: 1.0
#
#    --//
#    Content-Type: text/cloud-config; charset="us-ascii"
#    MIME-Version: 1.0
#    Content-Transfer-Encoding: 7bit
#    Content-Disposition: attachment; filename="cloud-config.txt"
#
#    #cloud-config
#    cloud_final_modules:
#    - [scripts-user, always]
#
#    --//
#    Content-Type: text/x-shellscript; charset="us-ascii"
#    MIME-Version: 1.0
#    Content-Transfer-Encoding: 7bit
#    Content-Disposition: attachment; filename="userdata.txt"
#
#    #!/bin/bash -xe
#    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
#      sysctl -w net.ipv4.ip_forward=1
#      /sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
#    REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | awk -F'"' '/"region"/ { print $4 }')
#    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
#    aws --region $REGION ec2 modify-instance-attribute --instance-id "$INSTANCE_ID" --no-source-dest-check
#    --//--
#  EOF
#
#  # Required for NAT
#  source_dest_check = false
#
#  tags = {
#    Name = "NATandBastion"
#  }
#
#  # Tags don't work on spot instance as per this ticket: https://github.com/hashicorp/terraform/issues/3263
#  # hence the workaround below (doesnt' work)
#  # when troubleshooting, look at this: https://github.com/int128/terraform-aws-nat-instance/blob/master/main.tf
#
#  # provisioner "local-exec" {
#  #  command = "aws ec2 create-tags --resources ${aws_spot_instance_request.natAndBastionInstance.spot_instance_id} --tags Key=Name,Value=ec2-resource-name"
#  #}
#}
#
#output natAndBastionInstancePubIp {
#  value = aws_spot_instance_request.natAndBastionInstance.public_ip
#}
#
#output natAndBastionInstancePrivIp {
#  value = aws_spot_instance_request.natAndBastionInstance.private_ip
#}

###################
# Private Subnets
###################

resource "aws_subnet" "sigman_private_1" {
  cidr_block = "10.0.3.0/24"
  vpc_id = aws_vpc.sigman.id
  availability_zone = "eu-central-1a"

  tags = {
    Name = "sigman-private-1"
  }
}

resource "aws_subnet" "sigman_private_2" {
  cidr_block = "10.0.4.0/24"
  vpc_id = aws_vpc.sigman.id
  availability_zone = "eu-central-1b"

  tags = {
    Name = "sigman-private-2"
  }
}

resource "aws_route_table" "sigman_private" {
  #  depends_on = [aws_spot_instance_request.natAndBastionInstance]

  vpc_id = aws_vpc.sigman.id

  # https://github.com/hashicorp/terraform-provider-aws/issues/1426
  #  route {
  #    cidr_block = "0.0.0.0/0"
  #    # nat_gateway_id = ""
  #    # gateway_id = aws_internet_gateway.sigman_igw.id
  ##    instance_id = aws_instance.natAndBastionInstance.id
  #    # without this, plan reapply will show a change due to this populated
  #    network_interface_id = aws_instance.natAndBastionInstance.primary_network_interface_id
  #  }

  tags = {
    Name = "sigman-private"
  }
}

# https://github.com/hashicorp/terraform-provider-aws/issues/1426
# inline route in route table was always showing a change (instance id auto populated or net_int_id if instance_id was provided)
resource "aws_route" "nat" {
  route_table_id = aws_route_table.sigman_private.id
  network_interface_id = aws_instance.nat_and_bastion-instance.primary_network_interface_id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "private_1" {
  route_table_id = aws_route_table.sigman_private.id
  subnet_id = aws_subnet.sigman_private_1.id
}

resource "aws_route_table_association" "private_2" {
  route_table_id = aws_route_table.sigman_private.id
  subnet_id = aws_subnet.sigman_private_2.id
}
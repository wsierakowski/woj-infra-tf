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

# Hint: Generate pub from pem:
# $ ssh-keygen -y -f ~/Downloads/privkey.pem > ~/Downloads/pubkey.pub

resource "aws_key_pair" "sigman_key" {
  key_name   = "sigman_key"
  public_key = "${file("~/Downloads/sigman.pub")}"
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
  subnet_id = aws_subnet.sigman_public_2.id
}

###################
# NATandBastion
###################

# SG
resource "aws_security_group" "natAndBastionInstanceSG" {
  name = "nat_bastion_SG"
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
resource "aws_instance" "natAndBastionInstance" {
  ami = "ami-08b9633fe44dfcba1"
  instance_type = "t3.nano"
  subnet_id = aws_subnet.sigman_public_1.id
  associate_public_ip_address = true
  key_name = aws_key_pair.sigman_key.key_name

  vpc_security_group_ids = [
    aws_security_group.natAndBastionInstanceSG.id
  ]
  depends_on = [aws_security_group.natAndBastionInstanceSG]

  # User-data script to enable NAT capabilities
  #    wrapped into cloud-config to allow running on every instance run
  #    rather than just the initial launch

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
    Name = "NATandBastion"
  }
}

output natAndBastionInstancePubIp {
  value = aws_instance.natAndBastionInstance.public_ip
}

output natAndBastionInstancePrivIp {
  value = aws_instance.natAndBastionInstance.private_ip
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
#  depends_on = [aws_spot_instance_request.natAndBastionInstance]

  vpc_id = aws_vpc.sigman_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    # nat_gateway_id = ""
    # gateway_id = aws_internet_gateway.sigman_igw.id
    instance_id = aws_instance.natAndBastionInstance.id
  }

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
# Private Subnet Instance (temporarily until ASG is created)
###################

# SG
resource "aws_security_group" "privateInstanceSG" {
  name = "private_instance_SG"
  description = "SG for private instance"
  vpc_id = aws_vpc.sigman_vpc.id

  # PING only from VPC
  ingress {
    from_port = -1
    protocol = "icmp"
    to_port = -1
    cidr_blocks = ["10.0.0.0/16"]
  }

  # SSH only from VPC
  ingress {
    from_port = 22
    protocol = "tcp"
    to_port = 22
    cidr_blocks = [
      "10.0.0.0/16"]
  }

  # Allow all traffic out
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    # Can't reach NAT Instance with this setting for some reason
#    cidr_blocks      = ["10.0.0.0/16"]
    cidr_blocks      = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

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
resource "aws_spot_instance_request" "privateSpotInstance" {
  ami = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.nano"
  subnet_id = aws_subnet.sigman_private_1.id
  key_name = aws_key_pair.sigman_key.key_name

  spot_price = "0.006"
  spot_type = "one-time"
  # Terraform will wait for the Spot Request to be fulfilled, and will throw
  # an error if the timeout of 10m is reached.
  wait_for_fulfillment = true

  vpc_security_group_ids = [
    aws_security_group.privateInstanceSG.id
  ]

  depends_on = [aws_security_group.privateInstanceSG]

  tags = {
    Name = "privateSpotInstance1"
  }
}

output privateInstanceIp {
  value = aws_spot_instance_request.privateSpotInstance.private_ip
}

###################
# Private Subnet ASG
###################

data "template_file" "launch_template_userdata" {
  template = <<EOF
#!/bin/bash
git clone https://github.com/wsierakowski/demo-njs-app.git
cd demo-njs-app
npm i
npm start
  EOF
}

resource "aws_launch_template" "demo-njs-app" {

  name = "demo-njs-app"
  image_id = "ami-077f7be394e6e7874"
  instance_type = "t3.micro"
  key_name = aws_key_pair.sigman_key.key_name

#  iam_instance_profile {
#    name = "test"
#  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 8
      volume_type = "gp2"
      delete_on_termination = true
    }
  }

  vpc_security_group_ids = [aws_security_group.privateInstanceSG.id]

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "test"
    }
  }

  # https://github.com/hashicorp/terraform-provider-aws/issues/5530
  user_data = base64encode(data.template_file.launch_template_userdata.rendered)
}

/*
TODOs:
- add NATs
- add ALB
- add ASG running from spot instances form launch template in priv subnet

terraform state list
*/
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
    # without this, plan reapply will show a change due to this populated
    network_interface_id = aws_instance.natAndBastionInstance.primary_network_interface_id
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

  # 3000 only from VPC for nodejs web app port
  ingress {
    from_port = 3000
    protocol = "tcp"
    to_port = 3000
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

data "template_file" "demo-njs-app_userdata" {
  template = <<EOF
#!/bin/bash
git clone https://github.com/wsierakowski/demo-njs-app.git
cd demo-njs-app
npm i
npm start
  EOF
}

resource "aws_launch_template" "demo-njs-app-lt" {

  name = "demo-njs-app-lt"

  // TODO, this should have been searched and found in case the AMI is copied to other regions
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
      Name = "test-bla-bla"
      Name2 = "test-bla-bla"
    }
  }

  # https://github.com/hashicorp/terraform-provider-aws/issues/5530
  user_data = base64encode(data.template_file.demo-njs-app_userdata.rendered)
}

resource "aws_autoscaling_group" "demo-njs-app-asg" {
  name = "demo-njs-app-asg"
#  availability_zones = ["eu-central-1a", "eu-central-1b"]
  vpc_zone_identifier = [aws_subnet.sigman_private_1.id, aws_subnet.sigman_private_2.id]
  desired_capacity = 1
  min_size = 0
  max_size = 3

  # Required to redeploy without an outage.
  lifecycle {
    create_before_destroy = true
    # As per the note here https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_attachment
    # and discussion here: https://github.com/hashicorp/terraform-provider-aws/issues/14540#issuecomment-680099770
    ignore_changes = [load_balancers, target_group_arns]
  }

  launch_template {
    id = aws_launch_template.demo-njs-app-lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "DemoNjsAppASGInstance"
    propagate_at_launch = true
  }
}

# https://github.com/hashicorp/terraform-provider-aws/issues/511#issuecomment-624779778
data "aws_instances" "asg_instances_meta" {
  # to avoid "Error: Your query returned no results. Please change your search criteria and try again."

depends_on = [aws_autoscaling_group.demo-njs-app-asg]
  instance_tags = {
    # Use whatever name you have given to your instances
    Name = "DemoNjsAppASGInstance"
  }
}

output "asg_private_ips" {
  description = "Private IPs of ASG instances"
  value = data.aws_instances.asg_instances_meta.private_ips
}

#Metric value
#
#-infinity          30%    40%          60%     70%             infinity
#-----------------------------------------------------------------------
#          -30%      | -10% | Unchanged  | +10%  |       +30%
#-----------------------------------------------------------------------
# Need to be two separate policies, one for scaling up and other down:
#   https://github.com/hashicorp/terraform-provider-aws/issues/10376

resource "aws_autoscaling_policy" "demo-njs-app-asg-scaling-policy-down" {
  name                   = "demo-njs-app-asg-scaling-policy-down"
  adjustment_type        = "PercentChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.demo-njs-app-asg.name
  policy_type = "StepScaling"

  # Those bounds values are added to the alarm's threshold value

  step_adjustment {
    scaling_adjustment          = -30
    metric_interval_upper_bound = -20
  }

  step_adjustment {
    scaling_adjustment          = -10
    metric_interval_lower_bound = -20
    metric_interval_upper_bound = -10
  }
}

resource "aws_autoscaling_policy" "demo-njs-app-asg-scaling-policy-up" {
  name                   = "demo-njs-app-asg-scaling-policy-up"
  adjustment_type        = "PercentChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.demo-njs-app-asg.name
  policy_type = "StepScaling"

  # Those bounds values are added to the alarm's threshold value

#  step_adjustment {
#    scaling_adjustment          = 0
#    metric_interval_lower_bound = -10
#    metric_interval_upper_bound = 10
#  }

  step_adjustment {
    scaling_adjustment          = 10
    metric_interval_lower_bound = 10
    metric_interval_upper_bound = 20
  }

  step_adjustment {
    scaling_adjustment          = 30
    metric_interval_lower_bound = 20
  }
}

resource "aws_cloudwatch_metric_alarm" "demo-njs-app-cpu-alarm" {
  alarm_name          = "demo-njs-app-cpu-over50-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = 60
  statistic = "Average"
  threshold = 50

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.demo-njs-app-asg.name
  }

  alarm_description = "This metric monitors EC2 CPU utilization"
  alarm_actions = [aws_autoscaling_policy.demo-njs-app-asg-scaling-policy-down.arn, aws_autoscaling_policy.demo-njs-app-asg-scaling-policy-up.arn]
}

###################
# ALB
###################

# SG
resource "aws_security_group" "demo-njs-app-alb-sg" {
  name = "demo-njs-app-alb-sg"
  description = "SG for private instance"
  vpc_id = aws_vpc.sigman_vpc.id

  ingress {
    from_port = 443
    protocol = "tcp"
    to_port = 443
    cidr_blocks = [
      "0.0.0.0/0"]
  }

  ingress {
    from_port = 80
    protocol = "tcp"
    to_port = 80
    cidr_blocks = [
      "0.0.0.0/0"]
  }

  # TODO: what if there was no egress specified? Should we actually allow all, SG are stateful.
  # Allow all traffic out
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    # Can't reach NAT Instance with this setting for some reason
    #    cidr_blocks      = ["10.0.0.0/16"]
    cidr_blocks      = ["0.0.0.0/0"]
  }

#  lifecycle {
#    create_before_destroy = true
#  }
}

resource "aws_lb_target_group" "demo-njs-app-tg" {
  name = "demo-njs-app-tg"
  port = 3000
  protocol = "HTTP"
  vpc_id = aws_vpc.sigman_vpc.id

  health_check {
    path = "/health"
    port = "traffic-port"
    # 5 consecutive health check successes
    healthy_threshold = 5
    # 2 consecutive health check failures
    unhealthy_threshold = 2
    timeout = 5
    interval = 30
    # Success codes
    matcher = "200"
  }
}

resource "aws_lb" "demo-njs-app-alb" {
  name = "demo-njs-app-alb"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.demo-njs-app-alb-sg.id]
  subnets = [aws_subnet.sigman_public_1.id, aws_subnet.sigman_public_2.id]

#  enable_deletion_protection = true
}

output "alb_dns_name" {
  description = "The DNS name of the load balancer."
  value = aws_lb.demo-njs-app-alb.dns_name
}

## TODO: this is failing, but look at this: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_attachment
#resource "aws_lb_target_group_attachment" "demo-njs-app-alb-attachment" {
#  target_group_arn = aws_lb_target_group.demo-njs-app-tg.arn
#  target_id        = aws_lb.demo-njs-app-alb.arn
#}
# =====================
resource "aws_autoscaling_attachment" "asg_attachment_test" {
  autoscaling_group_name = aws_autoscaling_group.demo-njs-app-asg.id
  alb_target_group_arn = aws_lb_target_group.demo-njs-app-tg.arn
}

# =====================
resource "aws_lb_listener" "demo-njs-app-alb-listener-http" {
  load_balancer_arn = aws_lb.demo-njs-app-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo-njs-app-tg.arn
  }
}

# https://stackoverflow.com/questions/64310497/terraform-aws-and-importing-existing-ssl-certificates
resource "aws_acm_certificate" "hahment-com-cert" {
  private_key = file("~/Downloads/klucz_prywatny_.txt")
  certificate_body = file("~/Downloads/certyfikat_.txt")
  certificate_chain = file("~/Downloads/certyfikat_posredni_.txt")

  tags = {
    domain = "hahment.com"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "demo-njs-app-alb-listener-https" {
  load_balancer_arn = aws_lb.demo-njs-app-alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.hahment-com-cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo-njs-app-tg.arn
  }
}

###################
# Route 53 hosted zone
###################

# TODO: look at this: https://github.com/hashicorp/terraform/issues/9289
data "aws_route53_zone" "wojsierak" {
  name         = "wojsierak.com."
}

resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.wojsierak.zone_id
#  name    = "dev.${data.aws_route53_zone.wojsierak.name}"
  name    = data.aws_route53_zone.wojsierak.name
  type    = "A"
  alias {
    name                   = aws_lb.demo-njs-app-alb.dns_name
    zone_id                = aws_lb.demo-njs-app-alb.zone_id
    evaluate_target_health = false
  }
}

# TODO: missing alarm - look at DemoNjsAppOver50
# hints: https://geekdudes.wordpress.com/2018/01/10/amazon-autosclaing-using-terraform/
# also: https://hands-on.cloud/terraform-recipe-managing-auto-scaling-groups-and-load-balancers/
# https://cloud.netapp.com/blog/blg-cloudwatch-monitoring-how-it-works-and-key-metrics-to-watch


#resource "aws_autoscaling_policy" "demo-njs-app-asg-scaling-policy" {
#  name                   = "demo-njs-app-asg-scaling-policy"
#  scaling_adjustment     = 4
#  adjustment_type        = "ChangeInCapacity"
#  cooldown               = 300
#  autoscaling_group_name = aws_autoscaling_group.demo-njs-app-asg.name
#}

/*
TODOs:
- why ASG gets recreated everytime I run it?
- add NLB
- add ASG running from spot instances from launch template in priv subnet
- provide consistency for naming convention,
- route53 (public and private hosted zone)
- DB

terraform state list
*/
# Conventions:
# - resource names:
#  - lowercase with underscores without repeating resource name
#  - singular nouns
#  - use the plural form in a variable name when type is list(...) or map(...)
# - tags at the bottom
# - use dashes in argument values that will be read by a human (vpc_id = "vpc-123")
# - outputs
#  - {name}_{type}_{attribute} (security_group_id, rds_cluster_instance_endpoints)
#  - include description for all outputs even if you think it is obvious

provider "aws" {
  region = "eu-central-1"
}

data "aws_caller_identity" "my_account" {}

# Hint: Generate pub from pem:
# $ ssh-keygen -y -f ~/Downloads/privkey.pem > ~/Downloads/pubkey.pub

resource "aws_key_pair" "sigman" {
  key_name   = "sigman"
  public_key = "${file("~/Downloads/sigman.pub")}"
}

###################
# Private Subnet Instance (temporarily until ASG is created)
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

## EC2 instance
resource "aws_spot_instance_request" "privateSpotInstance" {
  count = var.create_private_instance ? 1 : 0

  ami = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.nano"
  subnet_id = aws_subnet.sigman_private_1.id
  key_name = aws_key_pair.sigman.key_name

  spot_price = "0.006"
  spot_type = "one-time"
  # Terraform will wait for the Spot Request to be fulfilled, and will throw
  # an error if the timeout of 10m is reached.
  wait_for_fulfillment = true

  vpc_security_group_ids = [
    aws_security_group.private_instance.id
  ]

  depends_on = [aws_security_group.private_instance]

  tags = {
    Name = "privateSpotInstance1"
  }
}

output privateInstanceIp {
  value = var.create_private_instance == true ? null : aws_spot_instance_request.privateSpotInstance[*].private_ip
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
Must TODOs:

- update s3 policy to allow access to only one bucket
+ db state change alert
+ subdomain for bastion
+ wojsierak.com ssl cert issue (cert is only for hahment.com)
- cleanup
  - provide consistency for naming convention
    - https://www.terraform-best-practices.com/naming
  - make names derived from vars, for reuse, like here: https://github.com/hashicorp/terraform-provider-aws/issues/14540
  - format spaces indent around equal sign
+ check why ASG isn't seeing failing healthcheck - are healthchecks correctly set up?

Future improvements:
- remove all london setup (except for bastion host on spot instance to have a ref)
+ move sample file to a subdir and gitognore its content
- route 53 add hahment.com
- ASG
  - add ASG running from spot instances from launch template in priv subnet
  - add an autoscaling:EC2_INSTANCE_TERMINATING lifecycle hook to your Auto Scaling group
- make bastion a spot instance
- read logs from nodejs on ec2
  - remove sensitive info from app logs
  - https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/QuickStartEC2Instance.html
  - logrotate: https://stackoverflow.com/questions/65035838/how-can-i-rotate-log-files-in-pino-js-logger
  - CloudWatch agent: https://tomgregory.com/shipping-aws-ec2-logs-to-cloudwatch-with-the-cloudwatch-agent/
- add NLB
- route53 (public (other policies) and private hosted zone)
- route53 healthchecks: https://console.aws.amazon.com/route53/healthchecks/home?#/
- expose things like db name to vars (db will be named after that but also an sns topic)
- lambda: https://stackoverflow.com/questions/59032142/terraform-cloudwatch-event-that-notifies-sns
- s3 with SSE KMS + audit trail (https://www.bogotobogo.com/DevOps/AWS/aws-qwiklabs-KMS.php)
- EFS
- VPC peering
- S3 endpoint (interface vs gateway)
- VPN gateway
- Are DNS resolution and DNS hostnames attributes enabled for a VPC?
- AWS Storage Gateway
- add app authentication (Cognito?)
- Define the tags on the UAT and production servers and add a condition to the IAM policy which allows access to specific tags.
  - start using tags for every ec2
  - instances created by an ASG have that ASG id as a tag
- Run AWS Trusted Advisor to get optimisation tips
- Use SSM
 - to install software with RUN command
 - use automation to update AMIs
 - parameter store vs secrets manager (scoped with IAM policy)
 - configure lambda function that will be triggered by an eventbridge event - sent when run command completes
 - run run command when ec2 up event happens
- LEarn how to process logs through Athena
- Use AWS CodeDeploy to deploy node/java app instead of pulling directly from github and getting and decrypt param from SSM
- CloudWatch
  - set alert based on number of errors in the log (log could be console.log from nodejs lambda)
  - install cloud watch agent and collect stastd metrics from the app itself (CWAgent namespace)
  - read app logs
- Amazon inspector to scan for vulverabilities, once CVE is found, send sns which triggers lambda to call SSM to update the instance
- Build QuickSight to analize data in s3
- tf improvement - use conditional setup
  - count = var.create_public_subnets ? 1 : 0
+ EIP


terraform state list
*/
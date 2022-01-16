# TODO: tidy up, naming convention


###################
# Private Subnet ASG
###################

data "template_file" "demo-njs-app_userdata" {
  template = <<-EOF
    #!/bin/bash
    # AWS CLI will automatically pick the region this EC2 is run in
    export AWS_REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}')
    # to make it available in other session, handy for debugging
    echo "export AWS_REGION=$AWS_REGION" >> /etc/profile.d/load_env.sh
    chmod a+x /etc/profile.d/load_env.sh
    cd /home/ec2-user
    # Never run your app as a root
    sudo -u ec2-user bash -c '. /etc/profile.d/load_env.sh;echo "grzyb";echo $AWS_REGION;git clone https://github.com/wsierakowski/demo-njs-app.git;cd demo-njs-app;npm i;npm start > ~/demo-njs-app.log'
    EOF


  #  template = <<-EOF
  #    #!/bin/bash
  #    # AWS CLI will automatically pick the region this EC2 is run in
  #    export AWS_REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}')
  #    # to make it available in other session for debugging (TODO: this doesn't work)
  #    echo "export AWS_REGION=$AWS_REGION" >> /etc/profile.d/load_env.sh
  #    chmod a+x /etc/profile.d/load_env.sh
  #    cd /home/ec2-user
  #    pwd
  #    sudo -u ec2-user git clone https://github.com/wsierakowski/demo-njs-app.git
  #    cd demo-njs-app
  #    # TODO Never run your app as a root
  #    sudo -u ec2-user npm i
  #    sudo -u ec2-user npm start > /var/log/demo-njs-app.log
  ##    npm i
  ##    npm start > /var/log/demo-njs-app.log
  #    EOF
}

# If the script doesn't work as expected, check this log /var/log/cloud-init-output.log

resource "aws_launch_template" "demo-njs-app" {

  name = "demo-njs-app-lt"

  // TODO, this should have been searched and found in case the AMI is copied to other regions
  image_id = "ami-077f7be394e6e7874"
  instance_type = "t3.micro"
  key_name = aws_key_pair.sigman.key_name

  iam_instance_profile {
    name = aws_iam_role.demo-njs-app-role.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 8
      volume_type = "gp2"
      delete_on_termination = true
    }
  }

  vpc_security_group_ids = [aws_security_group.private_instance.id]

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

resource "aws_autoscaling_group" "demo-njs-app" {
  name = "demo-njs-app-asg"
  #  availability_zones = ["eu-central-1a", "eu-central-1b"]
  vpc_zone_identifier = [aws_subnet.sigman_private_1.id, aws_subnet.sigman_private_2.id]
  desired_capacity = 1
  min_size = 0
  max_size = 3
  health_check_type = "ELB"
  health_check_grace_period = 300

  # Required to redeploy without an outage.
  lifecycle {
    create_before_destroy = true
    # As per the note here https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_attachment
    # and discussion here: https://github.com/hashicorp/terraform-provider-aws/issues/14540#issuecomment-680099770
    ignore_changes = [load_balancers, target_group_arns]
  }

  launch_template {
    id = aws_launch_template.demo-njs-app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "DemoNjsAppASGInstance"
    propagate_at_launch = true
  }

  # Ensure ASG EC2 instances are stood up after the secret is created, otherwise secrets might be undefined at EC2 launch
  depends_on = [aws_secretsmanager_secret_version.demo_psql_db]
}

# https://github.com/hashicorp/terraform-provider-aws/issues/511#issuecomment-624779778
data "aws_instances" "asg_instances_meta" {
  # to avoid "Error: Your query returned no results. Please change your search criteria and try again."

  depends_on = [aws_autoscaling_group.demo-njs-app]
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
  autoscaling_group_name = aws_autoscaling_group.demo-njs-app.name
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
  autoscaling_group_name = aws_autoscaling_group.demo-njs-app.name
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
    AutoScalingGroupName = aws_autoscaling_group.demo-njs-app.name
  }

  alarm_description = "This metric monitors EC2 CPU utilization"
  alarm_actions = [aws_autoscaling_policy.demo-njs-app-asg-scaling-policy-down.arn, aws_autoscaling_policy.demo-njs-app-asg-scaling-policy-up.arn]
}
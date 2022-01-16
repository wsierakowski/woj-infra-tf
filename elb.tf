###################
# ALB
###################

# SG
resource "aws_security_group" "demo-njs-app-alb-sg" {
  name = "demo-njs-app-alb-sg"
  description = "SG for private instance"
  vpc_id = aws_vpc.sigman.id

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
  vpc_id = aws_vpc.sigman.id

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
  autoscaling_group_name = aws_autoscaling_group.demo-njs-app.id
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
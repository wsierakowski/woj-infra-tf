###################
# Route 53 hosted zone
###################

# TODO: look at this: https://github.com/hashicorp/terraform/issues/9289
data "aws_route53_zone" "wojsierak" {
  name         = "wojsierak.com."
}

resource "aws_route53_record" "main" {
  zone_id = data.aws_route53_zone.wojsierak.zone_id
  name    = data.aws_route53_zone.wojsierak.name
  type    = "A"
  alias {
    name                   = aws_lb.demo-njs-app-alb.dns_name
    zone_id                = aws_lb.demo-njs-app-alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "entry_subdomain" {
  name    = "entry.${data.aws_route53_zone.wojsierak.name}"
  type    = "A"
  zone_id = data.aws_route53_zone.wojsierak.zone_id
  ttl = 300
  records = [aws_instance.nat_and_bastion-instance.public_ip]
}
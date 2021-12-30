resource "aws_network_acl" "sigman_public_nacl" {
  vpc_id = aws_vpc.sigman_vpc.id
  subnet_ids = [aws_subnet.sigman_public_1.id, aws_subnet.sigman_public_2.id]

  ingress {
    rule_no    = 100
    protocol   = "icmp"
    from_port  = 0
    to_port    = 0
    icmp_type = -1
    icmp_code = -1
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  ingress {
    rule_no    = 101
    protocol   = "tcp"
    from_port  = 80
    to_port    = 80
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  ingress {
    rule_no    = 102
    protocol   = "tcp"
    from_port  = 443
    to_port    = 443
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  ingress {
    rule_no    = 103
    protocol   = "tcp"
    from_port  = 22
    to_port    = 22
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  ingress {
    rule_no    = 104
    protocol   = "tcp"
    from_port  = 1024
    to_port    = 65535
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  egress {
    rule_no    = 100
    protocol   = "icmp"
    from_port  = 0
    to_port    = 0
    icmp_type = -1
    icmp_code = -1
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  egress {
    rule_no    = 101
    protocol   = "tcp"
    from_port  = 1024
    to_port    = 65535
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  egress {
    rule_no    = 102
    protocol   = "tcp"
    from_port  = 80
    to_port    = 80
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  egress {
    rule_no    = 103
    protocol   = "tcp"
    from_port  = 443
    to_port    = 443
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  egress {
    rule_no    = 104
    protocol   = "tcp"
    from_port  = 22
    to_port    = 22
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  # not needed as rule 100 already includes this, but leaving just to highlight that
  # demo-njs-app runs on port 3000 in private subnet
  egress {
    rule_no    = 105
    protocol   = "tcp"
    from_port  = 3000
    to_port    = 3000
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  tags = {
    Name = "sigmanPublicNacl"
  }
}

resource "aws_network_acl" "sigman_private_nacl" {
  vpc_id = aws_vpc.sigman_vpc.id
  subnet_ids = [aws_subnet.sigman_private_1.id, aws_subnet.sigman_private_2.id]

  ingress {
    rule_no    = 100
    protocol   = "icmp"
    from_port  = 0
    to_port    = 0
    icmp_type = -1
    icmp_code = -1
    cidr_block = aws_vpc.sigman_vpc.cidr_block #"10.0.0.0/16"
    action     = "allow"
  }

  ingress {
    rule_no    = 101
    protocol   = "tcp"
    from_port  = 22
    to_port    = 22
    cidr_block = aws_vpc.sigman_vpc.cidr_block
    action     = "allow"
  }

  ingress {
    rule_no    = 102
    protocol   = "tcp"
    from_port  = 3000
    to_port    = 3000
    cidr_block = aws_vpc.sigman_vpc.cidr_block
    action     = "allow"
  }

  # to allow responses from the internet
  ingress {
    rule_no    = 103
    protocol   = "tcp"
    from_port  = 1024
    to_port    = 65535
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  egress {
    rule_no    = 100
    protocol   = "icmp"
    from_port  = 0
    to_port    = 0
    icmp_type = -1
    icmp_code = -1
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  egress {
    rule_no    = 101
    protocol   = "tcp"
    from_port  = 1024
    to_port    = 65535
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  egress {
    rule_no    = 102
    protocol   = "tcp"
    from_port  = 80
    to_port    = 80
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  egress {
    rule_no    = 103
    protocol   = "tcp"
    from_port  = 443
    to_port    = 443
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  egress {
    rule_no    = 104
    protocol   = "tcp"
    from_port  = 22
    to_port    = 22
    cidr_block = "0.0.0.0/0"
    action     = "allow"
  }

  tags = {
    Name = "sigmanPrivateNacl"
  }
}
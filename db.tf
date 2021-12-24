resource aws_db_instance sigman_db {
  allocated_storage = 10
  engine = "PostgreSQL"
  engine_version = "13.3"
  instance_class = "db.t3.micro"
  name = "sigman_db"
  # TODO: how to avoid storing plain text password here?
  username = "postgres"
  password = "grzyb"
  parameter_group_name = "default.postgres13"
  skip_final_snapshot = true
  multi_az = false

  # subnets
  # sg
  # https://github.com/terraform-aws-modules/terraform-aws-rds/blob/master/examples/complete-postgres/main.tf
}

# psql -h <hostname or ip address> -p <port number of remote machine> -d <database name which you want to connect> -U <username of the database server>

# SG
resource "aws_security_group" "sigman-psql-sg" {
  name = "sigman-psql_SG"
  description = "SG for psql db"
  vpc_id = aws_vpc.sigman_vpc.id

  # PING only from VPC
  ingress {
    from_port = 5432
    protocol = "tcp"
    to_port = 5432
    # TODO: are they right SGs?
    security_groups = [aws_security_group.demo-njs-app-alb-sg.id, aws_security_group.natAndBastionInstanceSG.id]
#    cidr_blocks = ["10.0.0.0/16"]
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
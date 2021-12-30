# TF Doc: https://learn.hashicorp.com/tutorials/terraform/aws-rds
# Read replica example: https://msameeduddin.medium.com/using-terraform-deploying-postgresql-instance-with-read-replica-in-aws-49e75012c0b3
# https://github.com/terraform-aws-modules/terraform-aws-rds/blob/master/examples/complete-postgres/main.tf

# It may take 5-7 minutes for AWS to provision the RDS instance.

provider "random" {}

resource "random_password" "db_password" {
  length = 20
  special = true
  override_special = "_%@"
}

resource "aws_db_subnet_group" "sigman_db_sg" {
  name = "sigman-db-sg"
  subnet_ids = [aws_subnet.sigman_private_1.id, aws_subnet.sigman_private_2.id]
  tags = {
    Name = "sigman-db-sg"
  }
}

# SG - not finished
resource "aws_security_group" "sigman_psql_sg" {
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
#    cidr_blocks = aws_vpc.sigman_vpc.cidr_block
    #    cidr_blocks = ["10.0.0.0/16"]
  }

#  # Allow all traffic out
#  egress {
#    from_port        = 0
#    to_port          = 0
#    protocol         = "-1"
#    # Can't reach NAT Instance with this setting for some reason
#    #    cidr_blocks      = ["10.0.0.0/16"]
#    cidr_blocks      = ["0.0.0.0/0"]
#  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "sigman_db_pg" {
  name   = "sigman_db_pg"
  family = "postgres13"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}

resource "aws_db_instance" "sigman_db" {
  identifier = "sigman_db"
  # The name of the database to create when the DB instance is created
  name = "sigman_db"
  instance_class = "db.t3.micro"
  allocated_storage = 5
  engine = "postgres"
  engine_version = "13.3"

  username = "postgres"
  password = random_password.db_password.result

  db_subnet_group_name = aws_db_subnet_group.sigman_db_sg.name
  vpc_security_group_ids = [aws_security_group.sigman_psql_sg.id]

#  parameter_group_name = "default.postgres13"
  parameter_group_name = aws_db_parameter_group.sigman_db_pg.name
  skip_final_snapshot = true
  multi_az = false
  storage_encrypted    = false
  publicly_accessible  = false

  # changes requiring instance reboot or degradation can be applied at maintenance window or can be applied immediately (causing outage)
  apply_immediately      = true
}

output "rds_hostname" {
  description = "RDS instance hostname"
  value = aws_db_instance.sigman_db.address
#  sensitive = true
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.sigman_db.port
  sensitive   = true
}

output "rds_username" {
  description = "RDS instance root username"
  value       = aws_db_instance.sigman_db.username
#  sensitive   = true
}

output "rds_password" {
  description = "RDS instance root password"
  value = aws_db_instance.sigman_db.password
}

# $ psql $(terraform output -raw rds_replica_connection_parameters)
output "rds_replica_connection_parameters" {
  description = "RDS replica instance connection parameters"
  value       = "-h ${aws_db_instance.sigman_db.address} -p ${aws_db_instance.sigman_db.port} -U ${aws_db_instance.sigman_db.username} postgres"
}


# Though some RDS configuration changes are safe to apply immediately, others (such as engine_version) require an instance
# reboot or may cause performance degradation (such as allocated_storage). By default, AWS will defer applying any changes
# that can cause degradation or outage until your next scheduled maintenance window.

# psql -h <hostname or ip address> -p <port number of remote machine> -d <database name which you want to connect> -U <username of the database server>

# psql -h $(terraform output -raw rds_hostname) -p $(terraform output -raw rds_port) -U $(terraform output -raw rds_username) postgres
# $ CREATE DATABASE hashicorp;
# \l \list
# \c demo_njs_app
# \dt



# psql -h wsi-psql-db-fromreplica1.ck10rjmx409c.eu-west-2.rds.amazonaws.com -p 5432 -U postgres
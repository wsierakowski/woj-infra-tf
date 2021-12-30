# TF Doc: https://learn.hashicorp.com/tutorials/terraform/aws-rds
# Read replica example: https://msameeduddin.medium.com/using-terraform-deploying-postgresql-instance-with-read-replica-in-aws-49e75012c0b3
# https://github.com/terraform-aws-modules/terraform-aws-rds/blob/master/examples/complete-postgres/main.tf

# Secrets manager:
# - https://automateinfra.com/2021/03/24/how-to-create-secrets-in-aws-secrets-manager-using-terraform-in-amazon-account/
# - https://stackoverflow.com/questions/65603923/terraform-rds-database-credentials
# - role: https://qalead.medium.com/terraform-aws-secretmanager-reading-secret-from-an-ec2-instance-using-iam-role-policy-and-a7a2b6922165

# It may take 5-7 minutes for AWS to provision the RDS instance.

provider "random" {}

#  Error: Error creating DB Instance: InvalidParameterValue: The parameter MasterUserPassword is not a valid password. Only printable ASCII characters besides '/', '@', '"', ' ' may be used.
resource "random_password" "db_password" {
  length = 20
  # Include special characters in the result
  special = true
  # Supply your own list of special characters to use for string generation.
  override_special = "/@\" "
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
    security_groups = [aws_security_group.privateInstanceSG.id, aws_security_group.natAndBastionInstanceSG.id]
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
  name   = "sigman-db-pg"
  family = "postgres13"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}

resource "aws_db_instance" "sigman_db" {
  identifier = "sigman-db"
  # The name of the database to create when the DB instance is created
  name = "demo_njs_app"
  instance_class = "db.t3.micro"
  allocated_storage = 5
  engine = "postgres"
  engine_version = "13.3"

  username = "postgres"
  password = random_password.db_password.result

  db_subnet_group_name = aws_db_subnet_group.sigman_db_sg.name
  vpc_security_group_ids = [aws_security_group.sigman_psql_sg.id]

#  parameter_group_name = "default.postgres13"
  # TODO: does this actually work?
  parameter_group_name = aws_db_parameter_group.sigman_db_pg.name
  skip_final_snapshot = true
  multi_az = false
  storage_encrypted    = true
  publicly_accessible  = false

  # changes requiring instance reboot or degradation can be applied at maintenance window or can be applied immediately (causing outage)
  apply_immediately      = true
}

resource "aws_secretsmanager_secret" "sigman_psql_db" {
  name = "sigman-psql-db"
}

resource "aws_secretsmanager_secret_version" "sigman_psql_db" {
  secret_id = aws_secretsmanager_secret.sigman_psql_db.id
  secret_string = <<EOF
{
  "username": "${aws_db_instance.sigman_db.username}",
  "password: "${random_password.db_password.result}",
  "engine": "postgres",
  "host": "${aws_db_instance.sigman_db.endpoint}",
  "port": "${aws_db_instance.sigman_db.port}",
  "dbInstanceIdentifier": "${aws_db_instance.sigman_db.identifier}"
}
EOF
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
  sensitive = true
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

# terraform output -raw rds_password

# $ CREATE DATABASE hashicorp;
# \l \list
# \c demo_njs_app
# \dt



# psql -h wsi-psql-db-fromreplica1.ck10rjmx409c.eu-west-2.rds.amazonaws.com -p 5432 -U postgres

#  demo_njs_app=> select * from books
#  demo_njs_app-> ;
#  id |         title          |                     description
#  ----+------------------------+------------------------------------------------------
#  1 | Rework                 | A better, faster, easier way to succeed in business.
#  2 | Deep Work              | Rules for Focused Success in a Distracted World.
#  3 | Thinking Fast and Slow | Learn about your system 1 and system 2
#  4 | Grzyb2                 | A book about stranger mushrooms
#  5 | Grzyb3                 | A book about strangest mushrooms
#  6 | Grzyb4                 | A book about strangest of the stranger mushrooms
#  7 | Grzyb5                 | A book about strangest of the strangest mushrooms
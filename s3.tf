resource "aws_s3_bucket" "demo-njs-app-bucket" {
  bucket = "demo-njs-app-bucket"
  acl = "private"
}

# to enable "block all public access"
resource "aws_s3_bucket_public_access_block" "demo-njs-app-bucket-access" {
  bucket = aws_s3_bucket.demo-njs-app-bucket.id

  block_public_acls   = true
  block_public_policy = true
  restrict_public_buckets = true
  ignore_public_acls = true
}

# sample object
locals {
  sample_file_content = <<-EOT
    Hello World Text File
    Testing creating files from Terraform
  EOT
}

resource "local_file" "sample_file" {
  filename = "temp/sample_file.txt"
  content = local.sample_file_content
}

resource "aws_s3_bucket_object" "sample_file" {
  bucket = aws_s3_bucket.demo-njs-app-bucket.id
  key    = "sample_file.txt"
  source = local_file.sample_file.filename
#  etag = filemd5(local_file.sample_file.content)
}


## VPC Gateway Endpoint to allow private subnets access s3 without NAT and to keep traffic to s3 internal to AWS
resource "aws_vpc_endpoint" "s3_demo-njs-bucket" {
  service_name = "com.amazonaws.eu-central-1.s3"
  vpc_id       = aws_vpc.sigman.id
  tags = {
    Name = "demo-njs-app-bucket_endpoint"
  }
}

# Prefix list is going to be automatically created and added to route table as the destination
# https://www.youtube.com/watch?v=5tyOCzZdXaQ
resource "aws_vpc_endpoint_route_table_association" "s3_demo-njs-bucket" {
  route_table_id  = aws_route_table.sigman_private.id
  vpc_endpoint_id = aws_vpc_endpoint.s3_demo-njs-bucket.id
}

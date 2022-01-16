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
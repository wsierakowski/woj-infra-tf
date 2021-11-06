provider "aws" {
  region = "eu-west-2"
}

data "aws_caller_identity" "my_account" {}

resource "aws_s3_bucket" "my_s3_bucket" {
  for_each = var.bucket_list

  bucket = "${each.key}-${data.aws_caller_identity.my_account.account_id}"
  acl    = "private"

  versioning {
    enabled = each.value.versioning
  }

  tags = {
    Terraform : "true"
    CostCenter : var.cost_center
    AliasName: each.value.aliasName
  }
}

output "first_bucket_name" {
  description = "First bucket name"
  value = aws_s3_bucket.my_s3_bucket["bucket1"].id
}

output "all_bucket_name" {
  description = "All bucket names"
  value = values(aws_s3_bucket.my_s3_bucket).*.id
}
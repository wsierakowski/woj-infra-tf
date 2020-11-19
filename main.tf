provider "aws" {
    region = "eu-west-1"
}

resource "aws_s3_bucket" "my_s3_bucket" {
    bucket = "my-example-20201119"
    acl = "private"
  
    versioning {
      enabled = true
    }

    tags = {
      Terraform: "true"
    }
}
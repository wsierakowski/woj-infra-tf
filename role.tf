# https://stackoverflow.com/questions/45002292/terraform-correct-way-to-attach-aws-managed-policies-to-a-role

#data "aws_iam_policy" "AmazonS3ReadOnlyAccess" {
#  arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
#}

data "aws_iam_policy_document" "read_access_to_demonjsapp_bucket" {
  version = "2012-10-17"

  statement {
    effect = "Allow"
    # list the content of the bucket
    actions = ["s3:ListBucket"]
    resources = [aws_s3_bucket.demo-njs-app-bucket.arn]
  }
  statement {
    effect = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.demo-njs-app-bucket.arn}/*"
      #"arn:aws:s3:::${var.s3_bucket_name}/home/&{aws:username}"
    ]
  }
}

resource "aws_iam_policy" "read_access_to_demonjsapp_bucket" {
  name   = "read_access_to_demonjsapp_bucket"
  path   = "/"
  policy = data.aws_iam_policy_document.read_access_to_demonjsapp_bucket.json
}

data "aws_iam_policy" "SecretsManagerReadWrite" {
  arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_role" "demo-njs-app-role" {
  name = "demo-njs-app-role"
  # indented heredoc string variant that is introduced by the <<-
  assume_role_policy = <<-EOF
  {
   "Version": "2012-10-17",
   "Statement": [
     {
       "Action": "sts:AssumeRole",
       "Principal": {
         "Service": "ec2.amazonaws.com"
       },
       "Effect": "Allow",
       "Sid": ""
     }
   ]
  }
  EOF
}

resource "aws_iam_role_policy_attachment" "demo-njs-app-role-s3-policy-attach" {
  role       = aws_iam_role.demo-njs-app-role.name
#  policy_arn = data.aws_iam_policy.AmazonS3ReadOnlyAccess.arn
  policy_arn = aws_iam_policy.read_access_to_demonjsapp_bucket.arn
}

resource "aws_iam_role_policy_attachment" "demo-njs-app-role-sm-policy-attach" {
  role       = aws_iam_role.demo-njs-app-role.name
  policy_arn = data.aws_iam_policy.SecretsManagerReadWrite.arn
}

resource "aws_iam_instance_profile" "demo-njs-app-role" {
  name = "demo-njs-app-role"
  role = aws_iam_role.demo-njs-app-role.name
}
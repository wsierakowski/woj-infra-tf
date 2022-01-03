# https://stackoverflow.com/questions/45002292/terraform-correct-way-to-attach-aws-managed-policies-to-a-role

data "aws_iam_policy" "AmazonS3ReadOnlyAccess" {
  arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

data "aws_iam_policy" "SecretsManagerReadWrite" {
  arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_role" "demo-njs-app-role" {
  name = "demo-njs-app-role"
  assume_role_policy = <<EOF
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
  policy_arn = data.aws_iam_policy.AmazonS3ReadOnlyAccess.arn
}

resource "aws_iam_role_policy_attachment" "demo-njs-app-role-sm-policy-attach" {
  role       = aws_iam_role.demo-njs-app-role.name
  policy_arn = data.aws_iam_policy.SecretsManagerReadWrite.arn
}

resource "aws_iam_instance_profile" "demo-njs-app-role" {
  name = "demo-njs-app-role"
  roles = [aws_iam_role.demo-njs-app-role.name]
}
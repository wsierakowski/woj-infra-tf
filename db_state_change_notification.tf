resource "aws_sns_topic" "demo_db_state_changes_topic" {
  name = "demo-db-state-changes-topic"
  fifo_topic = false
}

resource "aws_sns_topic_subscription" "demo_db_state_changes_email_updates" {
  endpoint  = var.sns_notifications_email
  protocol  = "email"
  topic_arn = aws_sns_topic.demo_db_state_changes_topic.arn
}

resource "aws_cloudwatch_event_rule" "demo_db_state_change_event_rule" {
  name = "capture-demo-db-state-change-events"
  description = "Capture demo-db state change events"

  event_pattern = <<-PATTERN
    {
      "source": ["aws.rds"],
      "detail-type": ["RDS DB Instance Event"]
    }
PATTERN
}

resource "aws_cloudwatch_event_target" "demo_db_state_change_event_target" {
  arn  = aws_sns_topic.demo_db_state_changes_topic.arn
  rule = aws_cloudwatch_event_rule.demo_db_state_change_event_rule.name
}

###########
# SNS Topic Access Policy to allow EventBridge event reach our topic
###########

# why using data for creating a policy? https://www.phillipsj.net/posts/terraforming-aws-iam-policies/
data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    sid = "1"
    effect = "Allow"
    principals {
      identifiers = ["events.amazonaws.com"]
      type        = "Service"
    }
    actions = ["sns:Publish"]
    resources = [aws_sns_topic.demo_db_state_changes_topic.arn]
  }

  statement {
    sid = "__default_statement_ID"
    actions = [
      "SNS:Subscribe",
      "SNS:SetTopicAttributes",
      "SNS:RemovePermission",
      "SNS:Receive",
      "SNS:Publish",
      "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes",
      "SNS:DeleteTopic",
      "SNS:AddPermission",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"

      values = [
        data.aws_caller_identity.my_account.account_id
      ]
    }

    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    resources = [
      aws_sns_topic.demo_db_state_changes_topic.arn
    ]
  }
}

resource "aws_sns_topic_policy" "demo_db_state_changes_topic_policy" {
  arn    = aws_sns_topic.demo_db_state_changes_topic.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

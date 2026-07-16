terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-2"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "target" {
  bucket = "cloud-guardrails-target-${random_id.suffix.hex}"
}

resource "aws_s3_bucket" "trail_logs" {
  bucket = "cloud-guardrails-trail-logs-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_policy" "trail_logs" {
  bucket = aws_s3_bucket.trail_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail_logs.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.trail_logs.arn}/AWSLogs/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "cloud-guardrails-trail"
  s3_bucket_name                = aws_s3_bucket.trail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "WriteOnly"
    include_management_events = true
  }

  depends_on = [aws_s3_bucket_policy.trail_logs]
}

resource "aws_cloudwatch_event_rule" "s3_public_access" {
  name = "cloud-guardrails-s3-public-access"
  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["PutBucketAcl", "PutBucketPolicy", "PutBucketPublicAccessBlock"]
      userIdentity = {
        arn = [{
          "anything-but" = { prefix = "arn:aws:sts::814117163773:assumed-role/cloud-guardrails-remediate-s3-role/" }
        }]
      }
    }
  })
}

resource "aws_cloudwatch_log_group" "eventbridge_test" {
  name              = "/aws/events/cloud-guardrails-test"
  retention_in_days = 1
}

resource "aws_cloudwatch_event_target" "test_log" {
  rule = aws_cloudwatch_event_rule.s3_public_access.name
  arn  = aws_cloudwatch_log_group.eventbridge_test.arn
}

resource "aws_cloudwatch_log_resource_policy" "eventbridge_to_logs" {
  policy_name = "cloud-guardrails-eventbridge-to-logs"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EventBridgeToCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource  = "${aws_cloudwatch_log_group.eventbridge_test.arn}:*"
      }
    ]
  })
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "remediate_s3_role" {
  name               = "cloud-guardrails-remediate-s3-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "remediate_s3_policy" {
  name = "remediate-s3-scoped"
  role = aws_iam_role.remediate_s3_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketPolicy",
          "s3:DeleteBucketPolicy"
        ]
        Resource = "arn:aws:s3:::cloud-guardrails-*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_cloudwatch_event_target" "s3_lambda" {
  rule = aws_cloudwatch_event_rule.s3_public_access.name
  arn  = "arn:aws:lambda:ap-southeast-2:814117163773:function:cloud-guardrails-remediate-s3"
}

resource "aws_lambda_permission" "allow_eventbridge_s3" {
  statement_id  = "AllowEventBridgeInvokeS3"
  action        = "lambda:InvokeFunction"
  function_name = "cloud-guardrails-remediate-s3"
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_public_access.arn
}

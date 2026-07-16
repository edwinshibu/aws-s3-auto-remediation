# Cloud Guardrails: Automated S3 Misconfiguration Detection and Remediation

A working AWS pipeline that detects when an S3 bucket becomes public and automatically fixes it within seconds, with no human involved. Built to understand how Cloud Security Posture Management (CSPM) tooling actually works under the hood, not just how to use one.

## The problem this addresses

Public S3 buckets are one of the most common causes of real cloud data breaches. Not sophisticated exploits, just a misconfigured permission or an overly broad policy left in place. Most organizations don't catch this by someone manually checking logs. They catch it because a tool is watching continuously and reacting automatically. This project builds a small, working version of that mechanism from scratch.

## What it does

1. An S3 bucket is deliberately made public (simulating a misconfiguration or an attacker's action)
2. AWS CloudTrail logs the exact API call that caused it, including who did it and when
3. Amazon EventBridge watches for that specific type of event and matches it
4. An AWS Lambda function is triggered automatically and reverts the bucket back to private
5. The system filters out its own remediation actions so it doesn't trigger itself in a loop

## Architecture

```
Public bucket policy applied
        |
        v
   CloudTrail (records the change, with full identity attribution)
        |
        v
   EventBridge rule (matches PutBucketPolicy / PutBucketAcl / PutBucketPublicAccessBlock,
                      excludes events caused by the remediation Lambda's own role)
        |
        v
   Lambda function (removes public policy, re-enables public access block)
        |
        v
   Bucket is private again, typically within 30-90 seconds
```

## Tools used

- **Terraform** for infrastructure as code (S3, CloudTrail, EventBridge, IAM roles)
- **AWS Lambda (Python 3.12)** for the remediation logic
- **AWS CLI** for manual testing and verification at each stage
- **boto3** for the AWS API calls inside the Lambda function

## How this was built, honestly

I have limited prior AWS and Python experience. This was my first hands-on cloud security project. I used AI assistance to help write the Terraform configuration and Python code, since I was learning both from close to zero. What I did myself: understood every resource and every line of code before applying it, tested each component in isolation before wiring it together, and diagnosed and fixed two real bugs that came up during the build (details below). The value of this project to me wasn't writing code from scratch. It was understanding exactly how detection and automated response actually work in a cloud environment, well enough to explain and defend every decision.

## Two real problems I hit and fixed

**Silent EventBridge delivery failure.** After writing the EventBridge rule and pointing it at a CloudWatch Logs group for testing, the rule matched correctly but nothing showed up in the logs. No error was thrown anywhere. The actual cause: EventBridge targets that write to CloudWatch Logs need an explicit resource policy granting `events.amazonaws.com` permission to write into that specific log group. The rule matching and the target having permission are two separate things, and AWS doesn't fail loudly when the second one is missing. Once I added the log resource policy, delivery worked immediately.

**Remediation feedback loop.** Once the Lambda was wired to EventBridge and tested against a real misconfiguration, it worked, but it kept firing every few seconds instead of once. The cause: the Lambda's own remediation actions (`PutBucketPublicAccessBlock`, deleting the bucket policy) are themselves API calls, which CloudTrail logs, which match the same EventBridge rule that triggers the Lambda. The system was reacting to its own fixes. I resolved this by adding an identity-based filter to the EventBridge rule, excluding any event where the CloudTrail `userIdentity.arn` matches the Lambda's own IAM role, so the rule now only reacts to changes made by something other than the remediation function itself.

## IAM design

The Lambda's execution role is scoped to exactly three S3 actions (`PutBucketPublicAccessBlock`, `GetBucketPolicy`, `DeleteBucketPolicy`) on resources matching this project's naming prefix, plus the minimum CloudWatch Logs permissions needed to write its own execution logs. It does not have broad S3 access, and it cannot touch any other bucket in the account.

## What I'd add next

- AWS Config rules running alongside the EventBridge path, to compare a continuous compliance-checking approach against this event-driven one
- SNS notification on every remediation action, so a real team would be alerted rather than only relying on logs
- A second detection and remediation path for an overly permissive security group (SSH open to 0.0.0.0/0), using GuardDuty findings instead of raw CloudTrail parsing
- Multi-account support using cross-account EventBridge, closer to how CSPM tools operate at scale

## Repository contents

- `terraform/` – all infrastructure definitions
- `lambda/remediate_s3/handler.py` – the remediation function
- `screenshots/` – CloudTrail events, EventBridge configuration, and Lambda execution logs from an actual run

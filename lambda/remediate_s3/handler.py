import boto3

s3 = boto3.client("s3")

def handler(event, context):
    detail = event.get("detail", {})
    bucket_name = detail.get("requestParameters", {}).get("bucketName")
    event_name = detail.get("eventName")

    print(f"Remediating {event_name} on bucket {bucket_name}")

    s3.put_public_access_block(
        Bucket=bucket_name,
        PublicAccessBlockConfiguration={
            "BlockPublicAcls": True,
            "IgnorePublicAcls": True,
            "BlockPublicPolicy": True,
            "RestrictPublicBuckets": True,
        },
    )

    try:
        s3.delete_bucket_policy(Bucket=bucket_name)
        print(f"Deleted public bucket policy on {bucket_name}")
    except Exception as e:
        print(f"No policy to delete or delete failed: {e}")

    return {"status": "remediated", "bucket": bucket_name}

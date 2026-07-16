from handler import handler

fake_event = {
    "detail": {
        "eventName": "PutBucketPolicy",
        "requestParameters": {
            "bucketName": "cloud-guardrails-target-a177362d"
        }
    }
}

result = handler(fake_event, None)
print("Result:", result)

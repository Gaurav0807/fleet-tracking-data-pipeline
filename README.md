# fleet-tracking-data-pipeline
Fleet tracking data pipeline using Aws , DBT, Terraform and Lambda ,




![Architecture](/architecture.png)



Reading data from SQS. S3 event -> "Records" contains bucket + key info

![SQS to Aws S3](/sns_topics_to_s3_bucket.png)
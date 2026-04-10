resource "aws_sns_topic" "s3_events" {
  name = "${local.prefix}-s3-landing-events"
}

resource "aws_sns_topic_policy" "allow_s3" {
  arn = aws_sns_topic.s3_events.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.s3_events.arn

        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:s3:::${var.data_bucket}"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "landing_notification" {
  bucket = var.data_bucket

  topic {
    topic_arn     = aws_sns_topic.s3_events.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "raw/vehicle_events/"
    filter_suffix = ".json"
  }

  depends_on = [aws_sns_topic_policy.allow_s3]
}
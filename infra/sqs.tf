
resource "aws_sqs_queue" "consumer_queue" {
  name                       = "${local.prefix}-consumer-queue"
  visibility_timeout_seconds = 300   # 5 min — must be >= Lambda timeout (120s)
  message_retention_seconds  = 86400 # 1 day
  receive_wait_time_seconds  = 10    # Long polling (saves API calls)
}


resource "aws_sqs_queue" "consumer_dlq" {
  name                      = "${local.prefix}-consumer-dlq"
  message_retention_seconds = 1209600 # 14 days
}


resource "aws_sqs_queue_redrive_policy" "consumer" {
  queue_url = aws_sqs_queue.consumer_queue.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.consumer_dlq.arn
    maxReceiveCount     = 3
  })
}


resource "aws_sqs_queue_policy" "allow_sns" {
  queue_url = aws_sqs_queue.consumer_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.consumer_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.s3_events.arn
          }
        }
      }
    ]
  })
}

#  Subscribe SQS to SNS 
resource "aws_sns_topic_subscription" "sqs_sub" {
  topic_arn = aws_sns_topic.s3_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.consumer_queue.arn
}

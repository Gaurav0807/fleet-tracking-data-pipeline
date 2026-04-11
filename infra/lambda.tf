
data "archive_file" "consumer_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/consumer"
  output_path = "${path.module}/../lambda/consumer.zip"
}


resource "aws_iam_role" "lambda_consumer" {
  name = "${local.prefix}-lambda-consumer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_consumer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


resource "aws_iam_role_policy" "lambda_s3" {
  name = "${local.prefix}-lambda-s3-policy"
  role = aws_iam_role.lambda_consumer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.data_bucket}",
          "arn:aws:s3:::${var.data_bucket}/*"
        ]
      }
    ]
  })
}


resource "aws_iam_role_policy" "lambda_glue" {
  name = "${local.prefix}-lambda-glue-policy"
  role = aws_iam_role.lambda_consumer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:GetTable",
          "glue:CreateTable",
          "glue:GetPartition",
          "glue:CreatePartition",
          "glue:BatchCreatePartition"
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${local.account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${local.account_id}:database/fleet-bronze-db",
          "arn:aws:glue:${var.aws_region}:${local.account_id}:table/fleet-bronze-db/*"
        ]
      }
    ]
  })
}


resource "aws_lambda_function" "consumer" {
  function_name    = "${local.prefix}-consumer"
  role             = aws_iam_role.lambda_consumer.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 120
  memory_size      = 256
  filename         = data.archive_file.consumer_lambda.output_path
  source_code_hash = data.archive_file.consumer_lambda.output_base64sha256

  layers = [var.pyarrow_layer_arn]

  environment {
    variables = {
      DATA_BUCKET   = var.data_bucket
      GLUE_DATABASE = aws_glue_catalog_database.bronze_db.name
      GLUE_TABLE    = "bronze_vehicle_events"
    }
  }
}


# SQS read — Lambda needs to poll messages from SQS
resource "aws_iam_role_policy" "lambda_sqs" {
  name = "${local.prefix}-lambda-sqs-policy"
  role = aws_iam_role.lambda_consumer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.consumer_queue.arn
      }
    ]
  })
}


resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.consumer_queue.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 5
  enabled          = true
}

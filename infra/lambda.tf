
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
          "arn:aws:glue:${var.aws_region}:${local.account_id}:database/${local.prefix}-db",
          "arn:aws:glue:${var.aws_region}:${local.account_id}:table/${local.prefix}-db/*"
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
      GLUE_DATABASE = aws_glue_catalog_database.fleet_db.name
      GLUE_TABLE    = "bronze_vehicle_events"
    }
  }
}


# --- Lake Formation Permissions ---
# Lake Formation adds an extra permission layer on top of IAM.
# Without these, Lambda gets AccessDeniedException even with IAM Glue permissions.

# Permission on the database (CREATE_TABLE, DESCRIBE)
resource "aws_lakeformation_permissions" "lambda_database" {
  principal   = aws_iam_role.lambda_consumer.arn
  permissions = ["CREATE_TABLE", "DESCRIBE"]

  database {
    name = aws_glue_catalog_database.fleet_db.name
  }
}

# Permission on all tables in the database (DESCRIBE, ALTER, INSERT)
resource "aws_lakeformation_permissions" "lambda_tables" {
  principal   = aws_iam_role.lambda_consumer.arn
  permissions = ["ALL"]

  table {
    database_name = aws_glue_catalog_database.fleet_db.name
    wildcard      = true
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

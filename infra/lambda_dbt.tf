# IAM Role for dbt Lambda
resource "aws_iam_role" "lambda_dbt" {
  name = "${local.prefix}-lambda-dbt-role"

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

resource "aws_iam_role_policy_attachment" "dbt_basic_execution" {
  role       = aws_iam_role.lambda_dbt.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# S3 — read bronze, write silver/gold + athena results
resource "aws_iam_role_policy" "dbt_s3" {
  name = "${local.prefix}-dbt-s3-policy"
  role = aws_iam_role.lambda_dbt.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${var.data_bucket}",
          "arn:aws:s3:::${var.data_bucket}/*"
        ]
      }
    ]
  })
}

# Glue — full access to all three databases
resource "aws_iam_role_policy" "dbt_glue" {
  name = "${local.prefix}-dbt-glue-policy"
  role = aws_iam_role.lambda_dbt.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:DeleteTable",
          "glue:BatchDeleteTable",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:CreatePartition",
          "glue:BatchCreatePartition",
          "glue:DeletePartition",
          "glue:BatchDeletePartition",
          "glue:GetTableVersion",
          "glue:GetTableVersions",
          "glue:DeleteTableVersion",
          "glue:BatchDeleteTableVersion"
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${local.account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${local.account_id}:database/fleet-bronze-db",
          "arn:aws:glue:${var.aws_region}:${local.account_id}:database/fleet-silver-db",
          "arn:aws:glue:${var.aws_region}:${local.account_id}:database/fleet-gold-db",
          "arn:aws:glue:${var.aws_region}:${local.account_id}:table/fleet-bronze-db/*",
          "arn:aws:glue:${var.aws_region}:${local.account_id}:table/fleet-silver-db/*",
          "arn:aws:glue:${var.aws_region}:${local.account_id}:table/fleet-gold-db/*"
        ]
      }
    ]
  })
}

# Athena — run queries
resource "aws_iam_role_policy" "dbt_athena" {
  name = "${local.prefix}-dbt-athena-policy"
  role = aws_iam_role.lambda_dbt.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StopQueryExecution",
          "athena:GetWorkGroup",
          "athena:GetDataCatalog"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda function (container image from ECR)
resource "aws_lambda_function" "dbt_runner" {
  function_name = "${local.prefix}-dbt-runner"
  role          = aws_iam_role.lambda_dbt.arn
  package_type  = "Image"
  image_uri        = "${aws_ecr_repository.dbt_runner.repository_url}:latest"
  source_code_hash = null_resource.docker_push.id
  timeout          = 900
  memory_size      = 1024

  environment {
    variables = {
      DBT_LOG_PATH              = "/tmp/dbt_logs"
      DBT_TARGET_PATH           = "/tmp/dbt_target"
      DBT_PACKAGES_INSTALL_PATH = "/tmp/dbt_packages"
    }
  }

  depends_on = [null_resource.docker_push]
}

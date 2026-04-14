# IAM Role for Step Functions
resource "aws_iam_role" "sfn_role" {
  name = "${local.prefix}-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "sfn_invoke_lambda" {
  name = "${local.prefix}-sfn-invoke-lambda"
  role = aws_iam_role.sfn_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.dbt_runner.arn
      }
    ]
  })
}

# Step Functions State Machine
resource "aws_sfn_state_machine" "dbt_pipeline" {
  name     = "${local.prefix}-dbt-pipeline"
  role_arn = aws_iam_role.sfn_role.arn

  definition = jsonencode({
    Comment = "Fleet Pulse dbt pipeline — run staging, silver, gold then test"
    StartAt = "dbt_run_staging"
    States = {
      dbt_run_staging = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.dbt_runner.arn
          Payload = {
            command = "run"
            select  = "staging"
          }
        }
        ResultPath = "$.staging_result"
        Next       = "dbt_run_silver"
      }
      dbt_run_silver = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.dbt_runner.arn
          Payload = {
            command = "run"
            select  = "silver"
          }
        }
        ResultPath = "$.silver_result"
        Next       = "dbt_run_gold"
      }
      dbt_run_gold = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.dbt_runner.arn
          Payload = {
            command = "run"
            select  = "gold"
          }
        }
        ResultPath = "$.gold_result"
        Next       = "dbt_test"
      }
      dbt_test = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.dbt_runner.arn
          Payload = {
            command = "test"
          }
        }
        ResultPath = "$.test_result"
        End        = true
      }
    }
  })
}

# --- EventBridge Scheduled Trigger (every hour) ---

resource "aws_iam_role" "eventbridge_sfn_role" {
  name = "${local.prefix}-eventbridge-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_start_sfn" {
  name = "${local.prefix}-eventbridge-start-sfn"
  role = aws_iam_role.eventbridge_sfn_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "states:StartExecution"
        Resource = aws_sfn_state_machine.dbt_pipeline.arn
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "dbt_schedule" {
  name                = "${local.prefix}-dbt-hourly"
  description         = "Trigger dbt pipeline every hour"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "dbt_sfn_target" {
  rule     = aws_cloudwatch_event_rule.dbt_schedule.name
  arn      = aws_sfn_state_machine.dbt_pipeline.arn
  role_arn = aws_iam_role.eventbridge_sfn_role.arn
}

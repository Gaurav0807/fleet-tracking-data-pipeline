terraform {
required_version = ">= 1.5.0"

required_providers {
    aws = {
    source  = "hashicorp/aws"
    version = "~> 5.0"
    }
    archive = {
    source  = "hashicorp/archive"
    version = "~> 2.0"
    }
}
}

provider "aws" {
    region = var.aws_region
}

data "aws_caller_identity" "current" {}

# Extracts the actual IAM role ARN from an SSO assumed-role session
# Input:  arn:aws:sts::123:assumed-role/RoleName/session
# Output: arn:aws:iam::123:role/aws-reserved/sso.amazonaws.com/RoleName
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
    account_id    = data.aws_caller_identity.current.account_id
    prefix        = "${var.project_name}-${var.environment}"
    caller_role   = data.aws_iam_session_context.current.issuer_arn
}

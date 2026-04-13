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

locals {
    account_id    = data.aws_caller_identity.current.account_id
    prefix        = "${var.project_name}-${var.environment}"
}
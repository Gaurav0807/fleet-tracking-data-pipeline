
variable "aws_region"{
    description = "Aws Region"
    type = string
    default = "us-east-1"
}

variable "project_name" {
    description = "Project name prefix for all resources"
    type        = string
    default     = "fleet-pulse"
}

variable "environment" {
    description = "Environment (dev, staging, prod)"
    type        = string
    default     = "dev"
}

variable "data_bucket" {
    description = "Single S3 bucket for all layers"
    type        = string
    default     = ""
}

variable "pyarrow_layer_arn" {
    description = "ARN of Lambda layer containing pyarrow (too large to bundle in zip)"
    type        = string
}


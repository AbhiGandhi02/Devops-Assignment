variable "aws_region" {
  description = "AWS region to create the bucket in"
  type        = string
  default     = "ap-south-1"
}

variable "bucket_prefix" {
  description = "Prefix of the bucket name; a random suffix keeps it globally unique"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 3-40 lowercase letters, digits or hyphens."
  }
}

variable "environment" {
  description = "Environment name used in tags"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Person responsible for the resources"
  type        = string
}

variable "noncurrent_version_days" {
  description = "Delete old object versions after this many days"
  type        = number
  default     = 30
}

variable "use_localstack" {
  description = "Send API calls to LocalStack instead of real AWS"
  type        = bool
  default     = false
}

variable "localstack_endpoint" {
  description = "LocalStack edge endpoint"
  type        = string
  default     = "http://localhost:4566"
}

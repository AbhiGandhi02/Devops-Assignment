# Step 0 - creates the S3 bucket that stores the remote Terraform state of ../ (the main stack).
# This tiny stack keeps a local state on purpose (the classic chicken-and-egg of remote state).
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

variable "state_bucket" {
  type    = string
  default = "readtrack-tfstate-24bcs10397"
}

provider "aws" {
  region                      = "ap-south-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true
  endpoints {
    s3  = var.localstack_endpoint
    sts = var.localstack_endpoint
    kms = var.localstack_endpoint
  }
}

# Customer-managed KMS key (rotated yearly) instead of the default S3-managed AES256 key
resource "aws_kms_key" "state" {
  description             = "readtrack state bucket encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_s3_bucket" "state" {
  bucket        = var.state_bucket
  force_destroy = true
  tags          = { Purpose = "terraform-remote-state", Owner = "abhi-gandhi" }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled" # every state write is a new object version -> easy rollback of a bad apply
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

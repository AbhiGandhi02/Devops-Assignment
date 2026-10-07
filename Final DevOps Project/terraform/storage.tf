resource "random_id" "suffix" {
  byte_length = 3
}

# Bucket for database backups (pg_dump from the cluster) and build artifacts such as scan reports.
# Customer-managed KMS key (rotated yearly) instead of the default S3-managed AES256 key
resource "aws_kms_key" "artifacts" {
  description             = "readtrack artifacts bucket encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.name}-artifacts-${random_id.suffix.hex}"
  force_destroy = true
  tags          = { Name = "${local.name}-artifacts" }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.artifacts.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    id     = "expire-old-backups"
    status = "Enabled"
    filter {
      prefix = "backups/"
    }
    expiration {
      days = 30
    }
  }
}

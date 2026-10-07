# Random suffix -> bucket names are global across all AWS accounts.
resource "random_id" "suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "demo" {
  bucket        = "${var.bucket_prefix}-${random_id.suffix.hex}"
  force_destroy = true # allow `terraform destroy` even when objects exist (demo only)

  tags = {
    Name        = "${var.bucket_prefix}-${random_id.suffix.hex}"
    Environment = var.environment
  }
}

# Keep every version of every object - protects against overwrite/delete mistakes.
resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt everything at rest with S3-managed keys (SSE-S3 / AES256).
resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access - the bucket is private.
resource "aws_s3_bucket_public_access_block" "demo" {
  bucket                  = aws_s3_bucket.demo.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: move logs to cheaper storage, expire old versions.
resource "aws_s3_bucket_lifecycle_configuration" "demo" {
  bucket     = aws_s3_bucket.demo.id
  depends_on = [aws_s3_bucket_versioning.demo]

  rule {
    id     = "logs-to-ia"
    status = "Enabled"
    filter {
      prefix = "logs/"
    }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }

  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_days
    }
  }
}

# Upload one object so the bucket is not empty.
resource "aws_s3_object" "readme" {
  bucket       = aws_s3_bucket.demo.id
  key          = "hello/README.txt"
  content      = "Created by Terraform for ${var.owner} (${var.environment}).\n"
  content_type = "text/plain"
  depends_on   = [aws_s3_bucket_server_side_encryption_configuration.demo]
}

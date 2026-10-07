resource "random_id" "suffix" {
  byte_length = 3
}

# Private bucket for the website assets; the EC2 instance reads index.html from it at boot.
resource "aws_s3_bucket" "assets" {
  bucket        = "${var.project}-assets-${random_id.suffix.hex}"
  force_destroy = true
  tags          = { Name = "${var.project}-assets" }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.assets.id
  key          = "site/index.html"
  content_type = "text/html"
  content      = templatefile("${path.module}/index.html.tftpl", { owner = var.owner, project = var.project })
  depends_on   = [aws_s3_bucket_server_side_encryption_configuration.assets]
}

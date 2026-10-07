# use_localstack = true  -> every AWS API call goes to LocalStack (http://localhost:4566)
# use_localstack = false -> real AWS, credentials from `aws configure` / environment
provider "aws" {
  region = var.aws_region

  access_key                  = var.use_localstack ? "test" : null
  secret_key                  = var.use_localstack ? "test" : null
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  s3_use_path_style           = var.use_localstack

  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      ec2 = var.localstack_endpoint
      iam = var.localstack_endpoint
      s3  = var.localstack_endpoint
      sts = var.localstack_endpoint
    }
  }

  default_tags {
    tags = {
      Project   = var.project
      Owner     = var.owner
      Session   = "19-cloud-terraform"
      ManagedBy = "terraform"
    }
  }
}

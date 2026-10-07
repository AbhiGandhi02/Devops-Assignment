terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state in S3 with native S3 locking (use_lockfile). The bucket comes from ./bootstrap.
  # Connection details live in backend-localstack.hcl:
  #   terraform init -backend-config=backend-localstack.hcl
  backend "s3" {}
}

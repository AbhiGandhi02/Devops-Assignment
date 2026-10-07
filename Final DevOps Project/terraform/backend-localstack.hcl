# Partial backend configuration for LocalStack (dummy credentials, not secrets).
# For real AWS: drop the endpoint/skip/credential lines and use your normal AWS profile.
bucket                      = "readtrack-tfstate-24bcs10397"
key                         = "final-project/terraform.tfstate"
region                      = "ap-south-1"
use_lockfile                = true
use_path_style              = true
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_requesting_account_id  = true
access_key                  = "test"
secret_key                  = "test"
endpoints = {
  s3  = "http://localhost:4566"
  sts = "http://localhost:4566"
}

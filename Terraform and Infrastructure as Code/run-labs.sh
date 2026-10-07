#!/usr/bin/env bash
# Terraform S3 demo - replays the full workflow in README.md against LocalStack.
# Start LocalStack first:  docker run -d --name localstack -p 4566:4566 localstack/localstack:4.12
set -u
cd "$(dirname "$0")/terraform-s3-demo"
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
export TF_CLI_ARGS="-no-color" TF_IN_AUTOMATION=1
# the AWS CLI talks to LocalStack with dummy credentials
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=ap-south-1
AWS="aws --endpoint-url http://localhost:4566"
rm -rf .terraform terraform.tfstate* tfplan

shot k18-01-init-fmt-validate
step "terraform version"
step "cat terraform.tfvars"
step "terraform init"
step "terraform fmt -recursive -diff"
step "terraform validate"

shot k18-02-plan
step "terraform plan -out=tfplan | grep -E '^  # |^Plan:|^Saved|^Changes to Outputs|^  \\+ [a-z_]+ += ' "

shot k18-03-apply
step "terraform apply -auto-approve tfplan"

shot k18-04-show-output
step "terraform output"
step "terraform output -raw bucket_name"
echo; echo
step "terraform state list"
step "terraform show | sed -n '/resource \"aws_s3_bucket\" \"demo\"/,/^}/p' | head -24"

shot k18-05-verify-aws-cli
B=$(terraform output -raw bucket_name)
step "$AWS s3 ls"
step "$AWS s3 ls s3://$B --recursive"
step "$AWS s3 cp s3://$B/hello/README.txt -"
step "$AWS s3api get-bucket-versioning --bucket $B"
step "$AWS s3api get-bucket-encryption --bucket $B --query 'ServerSideEncryptionConfiguration.Rules[0]'"
step "$AWS s3api get-public-access-block --bucket $B"
step "$AWS s3api get-bucket-lifecycle-configuration --bucket $B --query 'Rules[].{id:ID,status:Status}' --output table"

shot k18-06-drift-and-change
step "terraform plan -var environment=staging | grep -E '~|Plan:'"
step "terraform plan -detailed-exitcode >/dev/null; echo \"exit code \$? (0 = no changes, infrastructure matches code)\""

shot k18-07-destroy
step "terraform destroy -auto-approve | grep -E 'Destroying|Destruction complete|^Destroy complete|^Plan:'"
step "$AWS s3 ls"
step "terraform state list | wc -l"
rm -f tfplan

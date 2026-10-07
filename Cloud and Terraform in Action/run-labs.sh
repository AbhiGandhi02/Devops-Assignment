#!/usr/bin/env bash
# Cloud & Terraform in Action - replays the whole workflow in README.md against LocalStack.
#   docker run -d --name localstack -p 4566:4566 localstack/localstack:4.12
set -u
cd "$(dirname "$0")/terraform"
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
export TF_CLI_ARGS="-no-color" TF_IN_AUTOMATION=1
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=ap-south-1
AWS="aws --endpoint-url http://localhost:4566"
rm -rf .terraform terraform.tfstate* tfplan

shot k19-01-init-validate
step "terraform init | grep -E 'Installing|Installed|initialized'"
step "terraform fmt -recursive -check && echo 'fmt: all files formatted'"
step "terraform validate"
step "terraform providers"

shot k19-02-plan
step "terraform plan -out=tfplan | grep -E '^ *# |^Plan:|^ *data\\.|read during apply'"

shot k19-03-graph
step "terraform graph -type=plan | dot -Tsvg > ../dependency-graph.svg && echo 'dependency graph written to dependency-graph.svg'"
step "terraform graph -type=plan | grep -E '\\-> ' | sed -E 's/\\\"//g; s/\\[root\\] //g; s/ \\(expand\\)//g' | grep -vE 'provider|var\\.|output|meta|root|local\\.' | sort | head -30"

shot k19-04-apply
step "terraform apply -auto-approve tfplan | grep -E 'Creation complete|Apply complete|Still creating' | sed -E 's/ \\[id=.*//'"
step "terraform output"

shot k19-05-state
step "terraform state list"
step "terraform state show aws_instance.web | grep -E '^ +(ami|instance_type|subnet_id|private_ip|public_ip|iam_instance_profile|vpc_security_group_ids|http_tokens|encrypted|instance_state) '"

shot k19-06-verify-network
VPC=$(terraform output -raw vpc_id)
step "$AWS ec2 describe-vpcs --vpc-ids $VPC --query 'Vpcs[].{VPC:VpcId,CIDR:CidrBlock,State:State}' --output table"
step "$AWS ec2 describe-subnets --filters Name=vpc-id,Values=$VPC --query 'Subnets[].{Subnet:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,PublicIP:MapPublicIpOnLaunch,Tier:Tags[?Key==\`Tier\`]|[0].Value}' --output table"
step "$AWS ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC --query 'RouteTables[].{Table:Tags[?Key==\`Name\`]|[0].Value,Routes:join(\`, \`,Routes[].join(\` -> \`,[DestinationCidrBlock,GatewayId]))}' --output table"
step "$AWS ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC Name=group-name,Values=orbit-web-web-sg --query 'SecurityGroups[0].IpPermissions[].{Port:FromPort,Source:IpRanges[0].CidrIp,Why:IpRanges[0].Description}' --output table"

shot k19-07-verify-ec2-s3
step "$AWS ec2 describe-instances --filters Name=tag:Name,Values=orbit-web-web-1 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{ID:InstanceId,Type:InstanceType,State:State.Name,Subnet:SubnetId,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress}' --output table"
step "$AWS ec2 describe-instance-attribute --instance-id $(terraform output -raw instance_id) --attribute userData --query 'UserData.Value' --output text | base64 -d"
step "$AWS s3 ls s3://$(terraform output -raw assets_bucket) --recursive"
step "$AWS s3 cp s3://$(terraform output -raw assets_bucket)/site/index.html - | grep -E 'h1|<p>'"
step "$AWS iam get-role-policy --role-name orbit-web-web-role --policy-name read-assets-bucket --query 'PolicyDocument.Statement[].{Action:Action,Resource:Resource}' --output json"

shot k19-08-plan-destroy
step "terraform plan -detailed-exitcode >/dev/null; echo \"plan exit code \$? -> no drift\""
step "terraform plan -destroy | grep -E '^Plan:'"

shot k19-09-destroy
step "terraform destroy -auto-approve | grep -E 'Destruction complete|Destroy complete' | sed -E 's/ after .*//'"
step "$AWS ec2 describe-vpcs --filters Name=tag:Project,Values=orbit-web --query 'length(Vpcs)'"
step "terraform state list | wc -l"
rm -f tfplan

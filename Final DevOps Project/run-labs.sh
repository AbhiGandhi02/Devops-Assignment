#!/usr/bin/env bash
# Final DevOps Project - part 1: application, tests, Docker, Terraform (LocalStack) and the kind cluster.
# Output is saved as a transcript and rendered to screenshots/k21-*.png.
set -u
cd "$(dirname "$0")"
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
export KUBECONFIG="$PWD/.kubeconfig"
export FRONTEND_PORT=3100 BACKEND_PORT=8100     # 3000/8000 are busy on my laptop
VENV=${VENV:-/private/tmp/claude-501/-Users-aarham-Documents-Devops-Ass1/0f014ea5-3648-4dc1-ba01-b6db0f1d82de/scratchpad/venv-final}
source "$VENV/bin/activate"
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=ap-south-1
AWS="aws --endpoint-url http://localhost:4566"
TF="terraform -chdir=terraform"

# ------------------------------------------------------------------ application + tests
shot k21-01-pytest
step "cd application/backend && pytest -v --cov=app --cov-report=term 2>&1 | grep -E 'PASSED|FAILED|TOTAL|passed|failed' ; cd - >/dev/null"

shot k21-02-ruff-frontend-build
step "cd application/backend && ruff check app tests alembic && ruff format --check app tests alembic | tail -1; cd - >/dev/null"
step "cd application/frontend && npm ci --no-fund --silent && npm run build 2>&1 | tail -5; cd - >/dev/null"

# ------------------------------------------------------------------ docker
shot k21-03-compose-up
step "docker compose -f docker/docker-compose.yml down -v >/dev/null 2>&1; docker compose -f docker/docker-compose.yml up -d --build 2>&1 | grep -E ' Built| Started| Healthy'"
step "sleep 8; docker compose -f docker/docker-compose.yml ps --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'"
step "docker compose -f docker/docker-compose.yml logs backend 2>&1 | grep -E 'alembic|Uvicorn running' | head -4"

shot k21-04-compose-crud
step "curl -s -X POST localhost:3100/api/books -H 'Content-Type: application/json' -d '{\"title\":\"The Phoenix Project\",\"author\":\"Gene Kim\",\"status\":\"reading\",\"pages\":432}'"
step "curl -s -X POST localhost:3100/api/books -H 'Content-Type: application/json' -d '{\"title\":\"Site Reliability Engineering\",\"author\":\"Google\",\"status\":\"want_to_read\",\"pages\":552}'"
step "curl -s -X PUT localhost:3100/api/books/1 -H 'Content-Type: application/json' -d '{\"status\":\"finished\",\"rating\":5}'"
step "curl -s -o /dev/null -w 'DELETE /api/books/2 -> HTTP %{http_code}\n' -X DELETE localhost:3100/api/books/2"
step "curl -s localhost:3100/api/books; echo; curl -s localhost:3100/api/books/stats; echo"

shot k21-05-images-nonroot
step "docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' | grep -E 'REPOSITORY|readtrack'"
step "docker run --rm --entrypoint id readtrack-backend:compose; docker run --rm --entrypoint id readtrack-frontend:compose"
step "docker inspect readtrack-frontend:compose --format 'frontend user={{.Config.User}} ports={{.Config.ExposedPorts}}'"
step "docker compose -f docker/docker-compose.yml down -v 2>&1 | tail -2"

[ "${1:-all}" = "app" ] && exit 0
# ------------------------------------------------------------------ terraform on LocalStack
shot k21-06-terraform-bootstrap-init
step "curl -s localhost:4566/_localstack/health | python3 -c 'import json,sys; d=json.load(sys.stdin); print(\"LocalStack\", d[\"version\"], d[\"edition\"], {k: d[\"services\"][k] for k in (\"ec2\",\"iam\",\"s3\",\"kms\",\"sts\")})'"
step "terraform -chdir=terraform/bootstrap init -input=false -no-color | grep -E 'Installing|Installed|successfully'"
step "terraform -chdir=terraform/bootstrap apply -auto-approve -no-color | grep -E 'Creation complete|Apply complete|state_bucket'"
step "$TF init -input=false -no-color -backend-config=backend-localstack.hcl | grep -E 'backend|Installed|successfully'"
step "$TF fmt -check -recursive && $TF validate -no-color"

shot k21-07-terraform-plan
step "$TF plan -no-color -out=tfplan | grep -E '^  # |Plan:'"

shot k21-08-terraform-apply
step "$TF apply -no-color tfplan | grep -E 'Apply complete' ; $TF output -no-color"

shot k21-09-aws-resources
step "$AWS ec2 describe-vpcs --filters Name=tag:Project,Values=readtrack --query 'Vpcs[].[VpcId,CidrBlock,Tags[?Key==\`Name\`]|[0].Value]' --output table"
step "$AWS ec2 describe-subnets --filters Name=tag:Project,Values=readtrack --query 'Subnets[].[SubnetId,CidrBlock,AvailabilityZone,Tags[?Key==\`Tier\`]|[0].Value]' --output table"
step "$AWS iam list-roles --query 'Roles[?contains(RoleName,\`readtrack\`)].RoleName' --output text; $AWS s3 ls | grep readtrack"
step "$AWS s3 ls s3://readtrack-tfstate-24bcs10397 --recursive"

shot k21-10-terraform-eks-plan
step "$TF plan -no-color -var enable_eks=true | grep -E 'aws_eks|name *=|instance_types|desired_size|version *=|Plan:' | grep -vE 'node_group_name_prefix|tags' | head -22"

shot k21-11-terraform-destroy
step "$TF destroy -auto-approve -no-color | grep -E 'Destruction complete|Destroy complete' | tail -6"
step "$AWS ec2 describe-vpcs --filters Name=tag:Project,Values=readtrack --query 'length(Vpcs)'"
step "$TF apply -auto-approve -no-color | grep -E 'Apply complete'"

# ------------------------------------------------------------------ kind cluster (Terraform) + add-ons
shot k21-12-kind-cluster
step "terraform -chdir=terraform/kind-cluster state list; terraform -chdir=terraform/kind-cluster output -no-color"
step "kubectl get nodes -o wide | awk '{print \$1, \$2, \$3, \$5, \$6}' | column -t"
step "kubectl get pods -n ingress-nginx -o wide | awk '{print \$1, \$3, \$7}' | column -t; kubectl top nodes"

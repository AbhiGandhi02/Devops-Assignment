#!/usr/bin/env bash
# Final DevOps Project - part 3: DevSecOps scans locally (same tools as the pipeline) and the gate.
set -u
cd "$(dirname "$0")"
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
VENV=${VENV:-/private/tmp/claude-501/-Users-aarham-Documents-Devops-Ass1/0f014ea5-3648-4dc1-ba01-b6db0f1d82de/scratchpad/venv-final}
source "$VENV/bin/activate"
TAG=${TAG:-060be798b4caa5007d7ea4429f31c0304a9a0ce7}
BE=ghcr.io/abhigandhi02/readtrack-backend:$TAG
FE=ghcr.io/abhigandhi02/readtrack-frontend:$TAG
docker pull -q $BE >/dev/null; docker pull -q $FE >/dev/null
rm -rf reports

shot k21-26-sast
step "bandit -r application/backend/app -c security/bandit.yaml 2>&1 | sed -n '/Test results/,/High:/p' | grep -vE '^\s*$'"
step "docker run --rm -v \"\$PWD:/src\" -w /src semgrep/semgrep:latest semgrep scan --metrics=off --config p/python --config p/dockerfile application docker 2>&1 | grep -E 'Scanning|Ran |Findings|finding' | head -5"

shot k21-27-sca
step "pip-audit -r application/backend/requirements.txt 2>&1 | tail -2"
step "cd application/frontend && npm audit; cd - >/dev/null"

shot k21-28-secrets
step "docker run --rm -v \"\$PWD:/src\" -w /src ghcr.io/gitleaks/gitleaks:v8.24.0 dir . --config security/gitleaks.toml --redact --no-color --no-banner 2>&1 | tail -2"
step "printf 'DATABASE_URL=postgresql://readtrack:%s@db:5432/readtrack\n' \"\$(openssl rand -hex 12)\" > /tmp/leak-demo.env; docker run --rm -v /tmp/leak-demo.env:/scan/leak-demo.env -v \"\$PWD/security:/cfg\" ghcr.io/gitleaks/gitleaks:v8.24.0 dir /scan --config /cfg/gitleaks.toml --redact --no-color --no-banner -v 2>&1 | grep -E 'Finding|Secret|RuleID|File|leaks found'; rm -f /tmp/leak-demo.env"

shot k21-29-trivy-before-after
step "trivy image -q --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed readtrack-backend:with-pip 2>&1 | grep -E 'Total|urllib3|msgpack|setuptools' | cut -c1-120"
step "trivy image -q --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed $BE 2>&1 | grep -E 'Total|Report Summary|python-pkg|debian' | head -6"
step "trivy image -q --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed $FE 2>&1 | grep -E 'Total|alpine' | head -4"

shot k21-30-trivy-iac
step "trivy config -q -f json --severity HIGH,CRITICAL --skip-dirs application/frontend/node_modules --skip-dirs terraform/.terraform . | python3 security/trivy-config-summary.py"
step "grep -n -B2 -A1 'trivy:ignore' terraform/network.tf"

shot k21-31-security-gate
step "./security/scan-local.sh $TAG 2>&1 | sed -n '/Security gate/,\$p'"

shot k21-32-security-gate-fail
step "trivy image -q --scanners vuln --config security/trivy.yaml -f json -o reports/trivy-backend.json readtrack-backend:with-pip   # the first image I built, pip still inside"
step "python3 security/gate.py reports; echo \"gate exit code: \$?\""

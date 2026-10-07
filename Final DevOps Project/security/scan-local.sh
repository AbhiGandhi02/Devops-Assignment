#!/usr/bin/env bash
# Runs the same scanners as the CI pipeline on my laptop and then the security gate.
# usage: security/scan-local.sh <image-tag>     (reports land in ./reports, git-ignored)
set -uo pipefail
cd "$(dirname "$0")/.."
TAG=${1:-local}
R=reports; mkdir -p $R
BE=ghcr.io/abhigandhi02/readtrack-backend:$TAG
FE=ghcr.io/abhigandhi02/readtrack-frontend:$TAG

echo "== SAST: bandit"
bandit -q -r application/backend/app -c security/bandit.yaml -f json -o $R/bandit.json --exit-zero
echo "== SAST: semgrep"
docker run --rm -v "$PWD:/src" -w /src semgrep/semgrep:latest semgrep scan --quiet \
  --config p/python --config p/dockerfile --json -o $R/semgrep.json application docker >/dev/null 2>&1
echo "== SCA: pip-audit"
pip-audit -r application/backend/requirements.txt -f json -o $R/pip-audit.json >/dev/null 2>&1
echo "== SCA: npm audit"
(cd application/frontend && npm audit --json > ../../$R/npm-audit.json 2>/dev/null)
echo "== Secrets: gitleaks"
docker run --rm -v "$PWD:/src" -w /src ghcr.io/gitleaks/gitleaks:v8.24.0 dir . \
  --config security/gitleaks.toml --report-format json --report-path $R/gitleaks.json --exit-code 0 --redact >/dev/null 2>&1
echo "== Images: trivy"
trivy image -q --scanners vuln --config security/trivy.yaml --ignorefile security/.trivyignore -f json -o $R/trivy-backend.json $BE
trivy image -q --scanners vuln --config security/trivy.yaml --ignorefile security/.trivyignore -f json -o $R/trivy-frontend.json $FE
echo "== IaC: trivy config"
trivy config -q --severity HIGH,CRITICAL --ignorefile security/.trivyignore --skip-dirs application/frontend/node_modules -f json -o $R/trivy-config.json .
echo
python3 security/gate.py $R

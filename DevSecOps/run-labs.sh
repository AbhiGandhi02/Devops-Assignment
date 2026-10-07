#!/usr/bin/env bash
# DevSecOps - runs every security stage of the pipeline locally, then proves the
# security gate blocks a deliberately insecure copy of the app.
set -u
cd "$(dirname "$0")"
rm -rf .coverage .pytest_cache reports insecure-copy
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
PY=python:3.12-slim
GITLEAKS=ghcr.io/gitleaks/gitleaks:v8.24.0
SEMGREP=semgrep/semgrep:latest
IMAGE=orbit-vault:local

scan() { # dir -> writes dir/reports/*.json (quiet)
  local d=$1
  # secrets first, before the other reports (which quote rule examples) exist in the tree
  docker run --rm -v "$PWD/$d:/src" $GITLEAKS dir /src --config /src/security/gitleaks.toml --report-format json --report-path /src/.gitleaks.json --exit-code 0 --redact >/dev/null 2>&1
  mkdir -p "$d/reports" && mv "$d/.gitleaks.json" "$d/reports/gitleaks.json"
  docker run --rm -v "$PWD/$d:/src" -w /src $PY sh -c 'pip install -q bandit==1.8.6 pip-audit >/dev/null 2>&1;
      bandit -q -r app -c security/bandit.yaml -f json -o reports/bandit.json --exit-zero;
      pip-audit -r requirements.txt -f json -o reports/pip-audit.json >/dev/null 2>&1 || true'
  docker run --rm -v "$PWD/$d:/src" -w /src $SEMGREP semgrep scan --config p/python --config p/flask --json -o reports/semgrep.json -q app >/dev/null 2>&1
}

shot k17-01-unit-tests
step "docker run --rm -v \"\$PWD:/src\" -w /src $PY sh -c 'pip install -q -r requirements-dev.txt 2>/dev/null; pytest -q --cov=app --cov-report=term-missing'"

shot k17-02-sast
step "docker run --rm -v \"\$PWD:/src\" -w /src $PY sh -c 'pip install -q bandit==1.8.6 2>/dev/null; bandit -r app -c security/bandit.yaml' | sed -n '/Test results/,/High:/p'"
step "docker run --rm -v \"\$PWD:/src\" -w /src $SEMGREP semgrep scan --config p/python --config p/flask --metrics=off app 2>&1 | grep -E 'Ran|Findings|findings|Scan' | head -5"

shot k17-03-sca-secrets
step "docker run --rm -v \"\$PWD:/src\" -w /src $PY sh -c 'pip install -q pip-audit 2>/dev/null; pip-audit -r requirements.txt'"
step "docker run --rm -v \"\$PWD:/src\" $GITLEAKS dir /src --config /src/security/gitleaks.toml --redact 2>&1 | tail -3"

shot k17-04-image-scan
step "docker build -q --build-arg APP_VERSION=local -t $IMAGE ."
step "trivy image -q --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed $IMAGE 2>&1 | sed -n '/Report Summary/,/Legend/p' | head -12"
step "trivy config -q --severity HIGH,CRITICAL k8s/ Dockerfile 2>&1 | grep -E 'Tests|Failures|^$' | head -6; echo 'trivy config: Kubernetes manifests + Dockerfile checked'"

shot k17-05-gate-pass
scan .
trivy image -q --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --format json -o reports/trivy-image.json $IMAGE
step "ls reports"
step "python3 security/gate.py reports"
rm -rf reports

shot k17-06-gate-fail
rm -rf insecure-copy && mkdir insecure-copy && cp -R app security requirements.txt Dockerfile .dockerignore insecure-copy/
cat >> insecure-copy/app/main.py <<'PY'


def export_notes(filename):
    import subprocess
    # INSECURE on purpose: user input passed to a shell
    return subprocess.check_output("tar czf /tmp/" + filename + " /data", shell=True)
PY
# fake token generated at runtime so it never exists in a committed file
printf 'API_TOKEN = "ovt_%s"\n' "$(openssl rand -hex 16)" > insecure-copy/app/settings.py
printf 'Flask==2.2.0\ngunicorn==20.0.4\n' > insecure-copy/requirements.txt
step "diff <(cat requirements.txt) insecure-copy/requirements.txt; tail -4 insecure-copy/app/main.py; cat insecure-copy/app/settings.py | sed 's/ovt_.*/ovt_********\"/'"
scan insecure-copy
docker build -q -t orbit-vault:insecure insecure-copy >/dev/null 2>&1
trivy image -q --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --format json -o insecure-copy/reports/trivy-image.json orbit-vault:insecure
step "python3 security/gate.py insecure-copy/reports; echo \"gate exit code: \$?\""
rm -rf insecure-copy

shot k17-07-gh-pipeline
ID=$(gh run list -R AbhiGandhi02/Devops-Assignment -w 'S17 DevSecOps - orbit-vault' -L 1 --json databaseId -q '.[0].databaseId')
step "gh run view $ID -R AbhiGandhi02/Devops-Assignment | sed -n '1,/^ANNOTATIONS/p' | grep -v ANNOTATIONS"
GATE=$(gh run view $ID -R AbhiGandhi02/Devops-Assignment --json jobs -q '.jobs[] | select(.name=="8. Security gate") | .databaseId')
step "gh run view -R AbhiGandhi02/Devops-Assignment --job $GATE --log | grep -A7 'Security gate policy check' | cut -f3- | sed 's/^[0-9TZ:.-]* //'"
rm -rf .coverage .pytest_cache

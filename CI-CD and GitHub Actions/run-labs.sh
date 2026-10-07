#!/usr/bin/env bash
# CI/CD & GitHub Actions - runs locally the same stages the CI workflow runs on GitHub.
set -u
cd "$(dirname "$0")"
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
python3 -m venv .venv >/dev/null && . .venv/bin/activate && pip install -q -r requirements-dev.txt >/dev/null 2>&1

shot k16-01-local-lint-test
step "flake8 app tests && echo 'flake8: no issues'"
step "pytest -v --cov=app --cov-report=term"

shot k16-02-local-build
step "./build.sh"
step "cat build/build-info.txt"

shot k16-03-local-docker
step "docker build -q --build-arg APP_VERSION=local -t orbit-tasks:local ."
step "docker images orbit-tasks:local --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}'"
step "docker run -d --rm --name orbit-tasks -p 8000:8000 orbit-tasks:local"
sleep 3
step "curl -s localhost:8000/"
step "curl -s -X POST localhost:8000/tasks -H 'Content-Type: application/json' -d '{\"title\":\"write the CI pipeline\"}'"
step "curl -s localhost:8000/tasks"
step "docker ps --filter name=orbit-tasks --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'"
step "docker stop orbit-tasks"

shot k16-04-gh-runs
step "gh run list -R AbhiGandhi02/Devops-Assignment -w 'S16 CI - orbit-tasks' -L 3"
step "gh run list -R AbhiGandhi02/Devops-Assignment -w 'S16 CD - deploy orbit-tasks' -L 3"
CI=$(gh run list -R AbhiGandhi02/Devops-Assignment -w 'S16 CI - orbit-tasks' -L 1 --json databaseId -q '.[0].databaseId')
step "gh run view $CI -R AbhiGandhi02/Devops-Assignment | sed -n '1,/^ANNOTATIONS/p' | grep -v ANNOTATIONS"
step "gh api repos/AbhiGandhi02/Devops-Assignment/actions/runs/$CI/artifacts -q '.artifacts[] | \"\\(.name)  \\(.size_in_bytes) bytes\"'"
deactivate; rm -rf build .venv .pytest_cache .coverage coverage.xml

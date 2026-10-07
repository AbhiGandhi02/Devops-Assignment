#!/usr/bin/env bash
# Final DevOps Project - part 7: the end-to-end loop for one commit (7f20ce4, a CSS fix):
# git push -> pipeline green -> image in GHCR -> CI bumps gitops tag -> Argo CD rolls out prod.
set -u
cd "$(dirname "$0")"
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
export KUBECONFIG="$PWD/.kubeconfig"
R="-R AbhiGandhi02/Devops-Assignment"
RUN=${RUN:-37674093998}

shot k21-62-pipeline-jobs
step "gh run list $R -w 'Final Project - ReadTrack CI/CD' -L 6 | cut -f1,2,3,7,8 | column -t -s \$'\t'"
step "gh run view $RUN $R | sed -n '/JOBS/,/ANNOTATIONS/p' | grep -v ANNOTATIONS"

shot k21-63-commit-to-prod
step "git log --oneline -3 -- application/frontend/src/style.css gitops/values-gitops.yaml"
step "docker manifest inspect ghcr.io/abhigandhi02/readtrack-frontend:7f20ce4fd41f41648e7c0bd9092e7202b03cd1d8 | grep -m1 -E 'mediaType'"
step "kubectl -n argocd get application readtrack-prod -o jsonpath='{.status.sync.status} {.status.health.status} revision={.status.sync.revision}{\"\\n\"}'"
step "kubectl -n readtrack-prod get deploy -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image"
step "curl -s http://readtrack.localhost:8180/api/info; echo"

shot k21-64-git-history
step "git log --oneline --author='Abhi Gandhi' -- . ../.github/workflows/final-project.yml | head -22; echo; echo \"total commits touching the project: \$(git log --oneline -- . ../.github/workflows/final-project.yml | wc -l | tr -d ' ')\""

shot k21-65-ci-trivy-and-gate
step "gh run view $RUN $R --job 112973914808 --log | sed -E 's/^.*Z //' | grep -E 'readtrack-(backend|frontend):7f20|\\((debian|alpine)|Dockerfile|terraform/' | head -10"
step "gh run view $RUN $R --job 112974433901 --log | grep -E 'PASS|FAIL|GATE' | sed -E 's/^.*Z //'"

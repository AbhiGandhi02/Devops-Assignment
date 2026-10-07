#!/usr/bin/env bash
# Helm - replays every command in this section's README.
# Assumes the abhi-devops kind cluster from ../Kubernetes Fundamentals is running.
set -u
cd "$(dirname "$0")"
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
NS="-n helm-lab"
C=01-helm-commands/orbit-chart
P=03-mini-project/notes-chart
curl_svc() { # namespace svc localport -> prints the page through a port-forward
  kubectl port-forward -n "$1" "svc/$2" "$3:80" >/dev/null 2>&1 & local pf=$!
  sleep 3; curl -s "http://localhost:$3" | sed -e 's/<[^>]*>//g' | grep -v '^\s*$'; kill $pf; wait $pf 2>/dev/null
}

# ---------------- Task 1: Helm commands ----------------
shot k15-01-create-lint
step "helm version --short"
rm -rf "$C"; mkdir -p "$(dirname "$C")"
step "helm create $C"
step "find $C -type f | sort"
step "helm lint $C"
step "helm template orbit $C --set replicaCount=2 | grep -E '^kind:|replicas:|image:'"

shot k15-02-install-list-status
step "kubectl create namespace helm-lab"
step "helm install orbit $C $NS --set image.tag=1.26-alpine --wait --timeout 3m"
step "helm list $NS"
step "helm status orbit $NS | head -9"
step "kubectl get deploy,svc,pods $NS -l app.kubernetes.io/instance=orbit"

shot k15-03-get
step "helm get values orbit $NS"
step "helm get values orbit $NS --all | head -12"
step "helm get manifest orbit $NS | grep -E '^# Source|^kind:'"
step "helm get notes orbit $NS | head -4"
step "helm get metadata orbit $NS"

shot k15-04-repo-search
step "helm repo add podinfo https://stefanprodan.github.io/podinfo"
step "helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx"
step "helm repo update"
step "helm repo list"
step "helm search repo podinfo"
step "helm search repo ingress-nginx --versions | head -4"
step "helm search hub prometheus --max-col-width 60 | head -5"
step "helm show chart podinfo/podinfo | head -8"

shot k15-05-install-from-repo
step "helm install web podinfo/podinfo $NS --set replicaCount=2 --set ui.message='Hello from Abhi via Helm' --wait --timeout 3m"
step "kubectl get pods $NS -l app.kubernetes.io/name=web-podinfo"
kubectl port-forward $NS svc/web-podinfo 9898:9898 >/dev/null 2>&1 & PF=$!
sleep 3
step "curl -s localhost:9898 | grep -E 'hostname|version|message'"
kill $PF; wait $PF 2>/dev/null
step "helm uninstall web $NS"

# ---------------- Task 2: the rollback workflow ----------------
shot k15-06-upgrade
step "helm upgrade orbit $C $NS --set image.tag=1.27-alpine --set replicaCount=3 --wait --timeout 3m"
step "helm history orbit $NS"
step "kubectl get deploy orbit-orbit-chart $NS -o jsonpath='{.spec.replicas} replicas, image {.spec.template.spec.containers[0].image}{\"\\n\"}'"
step "helm get values orbit $NS --revision 2"

shot k15-07-bad-upgrade
step "helm upgrade orbit $C $NS --reuse-values --set image.tag=1.99-does-not-exist --wait --timeout 60s"
step "helm history orbit $NS"
step "kubectl get pods $NS -l app.kubernetes.io/instance=orbit"

shot k15-08-rollback
step "helm rollback orbit 2 $NS --wait --timeout 3m"
step "helm history orbit $NS"
step "kubectl get pods $NS -l app.kubernetes.io/instance=orbit"
step "kubectl get deploy orbit-orbit-chart $NS -o jsonpath='{.spec.replicas} replicas, image {.spec.template.spec.containers[0].image}{\"\\n\"}'"
step "helm list $NS"

shot k15-09-uninstall
step "helm uninstall orbit $NS"
step "helm list $NS"
step "kubectl get all $NS"

# ---------------- Task 3: mini project ----------------
shot k15-10-mini-dev
step "helm lint $P -f $P/values-prod.yaml"
step "helm install notes $P $NS --wait --timeout 3m"
step "kubectl get deploy,svc,cm $NS -l app.kubernetes.io/instance=notes"
step "curl_svc helm-lab notes-svc 8090"

shot k15-11-mini-prod
step "helm upgrade notes $P $NS -f $P/values-prod.yaml --wait --timeout 3m"
step "kubectl get pods $NS -l app=notes"
step "curl_svc helm-lab notes-svc 8091"
step "kubectl exec $NS deploy/notes-deploy -- printenv APP_NAME ENVIRONMENT"

shot k15-12-mini-rollback
step "helm upgrade notes $P $NS -f $P/values-prod.yaml --set app.message='Notes app - BROKEN release' --set image.tag=no-such-tag --wait --timeout 60s"
step "helm history notes $NS"
step "helm rollback notes 2 $NS --wait --timeout 3m"
step "helm history notes $NS"
step "curl_svc helm-lab notes-svc 8092     # immediately after the rollback"
sleep 75
step "curl_svc helm-lab notes-svc 8093     # and again ~75s later (ConfigMap volumes re-sync lazily)"
step "helm uninstall notes $NS"
step "kubectl delete namespace helm-lab"

#!/usr/bin/env bash
# Session 20 - Monitoring, Observability & GitOps - replays every command in this section's README.
# Assumes the abhi-devops kind cluster (with metrics-server) from the earlier sessions is running.
#
# usage: ./run-labs.sh [all|monitoring|observability|gitops]
set -u
cd "$(dirname "$0")"
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
PART=${1:-all}
M=01-monitoring
O=02-observability
G=03-gitops
# the argocd CLI opens its own port-forward to argocd-server (plain kubectl port-forward
# drops the HTTP/2 gRPC connection the CLI uses)
export ARGOCD_OPTS="--port-forward --port-forward-namespace argocd --plaintext"

# wait (silently) until an alert reaches a state; $1=alertname $2=firing|none
wait_alert() {
  for _ in $(seq 1 60); do
    if [ "$2" = none ]; then
      $M/alerts.sh prometheus | grep -q "^$1 " || return 0
    else
      $M/alerts.sh prometheus | grep -qE "^$1 +$2" && return 0
    fi
    sleep 5
  done
}
# wait until Argo CD has synced a Git revision that contains my commit $1 (other people
# push to the same repo, so the synced revision can be a newer commit on top of mine)
wait_argo_rev() {
  local start=$(date +%s) rev health
  while true; do
    rev=$(kubectl -n argocd get application guestbook -o jsonpath='{.status.sync.revision}')
    health=$(kubectl -n argocd get application guestbook -o jsonpath='{.status.operationState.phase}/{.status.operationState.syncResult.revision}')
    if [ -n "$rev" ] && [ "$health" = "Succeeded/$rev" ]; then
      git cat-file -e "$rev" 2>/dev/null || git fetch -q origin main
      git merge-base --is-ancestor "$1" "$rev" 2>/dev/null && break
    fi
    sleep 3
  done
  kubectl -n gitops-demo rollout status deploy/guestbook --timeout=180s >/dev/null
  echo "Argo CD synced main@${rev:0:7} (contains ${1:0:7}) after $(( $(date +%s) - start ))s - no manual sync command"
}
push_main() { # commit is already made; push it, retrying if another commit landed first
  for _ in 1 2 3 4 5; do
    git pull -q --rebase --autostash origin main && git push -q origin main 2>&1 && return 0
    sleep 3
  done
}

if [ "$PART" = all ] || [ "$PART" = monitoring ]; then
# ===================== Task 1: Monitoring =====================
shot k20-01-install-stack
step "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null; helm repo add grafana https://grafana.github.io/helm-charts >/dev/null; helm repo update >/dev/null; echo repos ready"
step "helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 92.1.0 -n monitoring --create-namespace -f $M/kube-prometheus-values.yaml --wait --timeout 10m | head -4"
step "helm upgrade --install loki grafana/loki --version 7.3.0 -n monitoring -f $M/loki-values.yaml --wait --timeout 10m | head -2"
step "helm upgrade --install alloy grafana/alloy --version 1.13.0 -n monitoring -f $M/alloy-values.yaml --wait --timeout 10m | head -2"
step "helm list -n monitoring"

shot k20-02-stack-pods
step "kubectl get pods -n monitoring -o wide | awk '{print \$1, \$2, \$3, \$7}' | column -t"
step "kubectl get crd | grep monitoring.coreos.com | awk '{print \$1}'"

shot k20-03-demo-app
step "kubectl apply -f $M/demo-app.yaml -f $O/jaeger.yaml -f $M/traffic.yaml"
kubectl -n observability rollout status deploy/podinfo-frontend --timeout=180s >/dev/null
kubectl -n observability rollout status deploy/podinfo-backend --timeout=180s >/dev/null
kubectl -n observability rollout status deploy/jaeger --timeout=180s >/dev/null
step "kubectl get deploy,svc,servicemonitor -n observability"

shot k20-04-app-metrics
step "kubectl -n observability exec deploy/traffic -- curl -s http://podinfo-frontend:9898/metrics | grep -E '^http_requests_total|^http_request_duration_seconds_count' | head -6"
sleep 30   # let Prometheus scrape the new targets a couple of times
step "$M/promql.sh 'sum by (job) (up)'"

shot k20-05-targets-up
step "$M/promql.sh 'up{namespace=\"observability\"}' | sed 's/endpoint=\"http\", //; s/, namespace=\"observability\"//'"
step "$M/promql.sh 'count(up == 1)'; $M/promql.sh 'count(up == 0)'"

shot k20-06-request-rate-latency
step "$M/promql.sh 'sum by (service) (rate(http_requests_total{namespace=\"observability\"}[1m]))'"
step "$M/promql.sh 'histogram_quantile(0.95, sum by (service, le) (rate(http_request_duration_seconds_bucket{namespace=\"observability\", path=\"echo\"}[2m])))'"

shot k20-07-cpu-memory-pods
step "kubectl top pods -n observability"
step "$M/promql.sh 'sum by (pod) (rate(container_cpu_usage_seconds_total{namespace=\"observability\", container!=\"\"}[2m]))'"
step "$M/promql.sh 'sum by (pod) (container_memory_working_set_bytes{namespace=\"observability\", container!=\"\"})' bytes"

shot k20-08-cpu-memory-nodes
step "kubectl top nodes"
step "$M/promql.sh '100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[2m])))' percent"
step "$M/promql.sh '100 * (1 - sum by (instance) (node_memory_MemAvailable_bytes) / sum by (instance) (node_memory_MemTotal_bytes))' percent"

shot k20-09-app-health
step "kubectl get deploy -n observability podinfo-frontend podinfo-backend"
step "kubectl describe pod -n observability -l tier=backend | grep -E '^Name:|Liveness|Readiness'"
step "kubectl -n observability exec deploy/traffic -- sh -c 'curl -s -w \" %{http_code}\n\" http://podinfo-backend:9898/healthz; curl -s -w \" %{http_code}\n\" http://podinfo-backend:9898/readyz'"
step "$M/promql.sh 'sum by (deployment) (kube_deployment_status_replicas_available{namespace=\"observability\"})'"

shot k20-10-logs-kubectl
step "kubectl logs -n observability -l tier=backend --prefix --tail=2 | cut -c1-190"
step "kubectl logs -n observability deploy/podinfo-frontend --since=1m | grep '\"uri\":\"/echo\"' | wc -l"
step "kubectl logs -n observability deploy/podinfo-frontend --since=1m | grep -o '\"msg\":\"[^\"]*\"' | sort | uniq -c | sort -rn"

shot k20-11-logs-loki
step "$M/logql.sh '{namespace=\"observability\", tier=\"backend\"} |= \"/echo\"' 4 | cut -c1-200"
step "$M/logql.sh 'sum by (app) (count_over_time({namespace=\"observability\"}[5m]))'"
step "$M/logql.sh 'sum by (namespace) (count_over_time({namespace=~\".+\"}[5m]))'"

shot k20-12-alert-rules
step "kubectl apply -f $M/alert-rules.yaml"
step "kubectl get prometheusrule -n observability"
sleep 20
step "$M/alerts.sh rules"
step "$M/alerts.sh prometheus"

shot k20-13-alert-app-down
step "kubectl scale deploy podinfo-backend -n observability --replicas=0"
wait_alert PodinfoDeploymentDown pending
step "$M/alerts.sh prometheus     # 'pending' = condition true, waiting for the for: 30s window"
wait_alert PodinfoDeploymentDown firing
wait_alert PodinfoTargetMissing firing
step "$M/alerts.sh prometheus"
sleep 20
step "$M/alerts.sh alertmanager"

shot k20-14-alert-resolved
step "kubectl scale deploy podinfo-backend -n observability --replicas=2"
kubectl -n observability rollout status deploy/podinfo-backend --timeout=120s >/dev/null
wait_alert PodinfoDeploymentDown none
wait_alert PodinfoTargetMissing none
step "kubectl get deploy podinfo-backend -n observability"
step "$M/alerts.sh prometheus"

shot k20-15-alert-high-cpu
kubectl delete pod cpu-hog -n observability --ignore-not-found >/dev/null   # start from a clean state on re-runs
step "kubectl apply -f $M/cpu-hog.yaml"
kubectl -n observability wait --for=condition=Ready pod/cpu-hog --timeout=120s >/dev/null
wait_alert ContainerHighCPU firing
step "kubectl top pod cpu-hog -n observability"
step "$M/promql.sh 'sum by (pod) (rate(container_cpu_usage_seconds_total{namespace=\"observability\", pod=\"cpu-hog\", container!=\"\"}[1m])) / 0.2 * 100' percent"
step "$M/alerts.sh prometheus"

shot k20-16-alert-traffic
kubectl delete job load-spike -n observability --ignore-not-found >/dev/null   # a Job only runs once
step "kubectl apply -f $M/load-spike.yaml"
wait_alert PodinfoHighRequestRate firing
step "$M/promql.sh 'sum by (service) (rate(http_requests_total{namespace=\"observability\"}[1m]))'"
step "$M/alerts.sh prometheus"
sleep 20
step "$M/alerts.sh alertmanager"

shot k20-17-grafana-dashboard
step "kubectl apply -f $M/grafana-dashboard.yaml"
step "kubectl get configmap -A -l grafana_dashboard=1 | grep -E '^(NAMESPACE|observability)'"
sleep 5
step "kubectl logs -n monitoring deploy/monitoring-grafana -c grafana-sc-dashboard --tail=200 | grep -i podinfo | tail -2 | cut -c1-170"
step "kubectl get secret -n monitoring monitoring-grafana -o jsonpath='{.data.admin-user}' | base64 -d; echo '  (password read the same way from .data.admin-password)'"
fi

if [ "$PART" = all ] || [ "$PART" = observability ]; then
# ===================== Task 2: Observability (traces) =====================
shot k20-18-jaeger
step "kubectl get deploy,svc -n observability -l app=jaeger"
step "kubectl -n observability get deploy podinfo-frontend -o jsonpath='{range .spec.template.spec.containers[0].command[*]}{@}{\"\\n\"}{end}' | grep -E 'otel|backend'"
step "kubectl -n observability get deploy podinfo-frontend -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{\"\\n\"}{end}' | grep OTEL"
step "$O/traces.sh services"

shot k20-19-trace
step "$O/traces.sh latest podinfo-frontend 'POST /echo'"

shot k20-20-three-pillars
T=$(kubectl logs -n observability -l tier=backend --tail=100 | grep '"uri":"/echo"' | tail -1 | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["trace_id"])')
sleep 10   # let the frontend flush its batch of spans
step "kubectl logs -n observability -l tier=backend --since=2m --tail=-1 | grep $T | grep -oE '\"(ts|msg|uri|method|trace_id)\":\"[^\"]*\"' | paste -sd' ' -    # 1) a LOG line carries the trace_id"
step "$O/traces.sh trace $T    # 2) the same id opens the TRACE in Jaeger"
step "$M/promql.sh 'sum by (service) (rate(http_request_duration_seconds_count{namespace=\"observability\", path=\"echo\"}[1m]))'    # 3) METRICS show the volume"
fi

if [ "$PART" = all ] || [ "$PART" = gitops ]; then
# ===================== Task 3: GitOps with Argo CD =====================
shot k20-21-argocd-install
step "helm repo add argo https://argoproj.github.io/argo-helm >/dev/null; helm repo update argo >/dev/null; echo repo ready"
step "helm upgrade --install argocd argo/argo-cd --version 10.10.0 -n argocd --create-namespace -f $G/argocd-values.yaml --wait --timeout 10m | head -4"
step "kubectl get pods -n argocd"
step "argocd login --username admin --password \"\$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)\" 2>&1 | tail -1"
step "argocd version 2>/dev/null | grep -E '^argocd|argocd-server'"

shot k20-22-argocd-app-create
step "cat $G/argocd-application.yaml | grep -vE '^\s*#'"
step "kubectl get ns gitops-demo"
step "kubectl apply -f $G/argocd-application.yaml"
kubectl -n argocd wait application/guestbook --for=jsonpath='{.status.health.status}'=Healthy --timeout=300s >/dev/null 2>&1
argocd app wait guestbook --sync --health --timeout 300 >/dev/null 2>&1

shot k20-23-argocd-synced
step "argocd app get guestbook | grep -vE '^(Server|URL|Target|Repo|SyncWindow|Sync Policy|Path|Project|Namespace|Name):'"
step "kubectl get deploy,svc,cm -n gitops-demo"

shot k20-24-git-change
step "sed -i '' -e 's/replicas: 2/replicas: 3/' -e 's/from Git - v1/from Git - v2/' $G/app/deployment.yaml"
step "git diff -U0 -- $G/app/deployment.yaml | grep -E '^[-+] '"
step "git commit -q -m 'GitOps demo: scale guestbook to 3 replicas and bump message to v2' -- $G/app/deployment.yaml && push_main && git log -1 --oneline"
REV=$(git rev-parse HEAD)
CHANGE=$REV
step "wait_argo_rev $REV"

shot k20-25-git-change-applied
step "kubectl get deploy guestbook -n gitops-demo"
step "kubectl -n gitops-demo exec deploy/guestbook -- curl -s localhost:9898 | grep message"
step "argocd app history guestbook"

shot k20-26-self-heal
step "kubectl scale deploy guestbook -n gitops-demo --replicas=6    # manual change = drift from Git"
step "kubectl get deploy guestbook -n gitops-demo"
sleep 8
step "kubectl get deploy guestbook -n gitops-demo    # Argo CD reverted it to the 3 in Git"
step "kubectl delete svc guestbook -n gitops-demo"
sleep 8
step "kubectl get svc guestbook -n gitops-demo    # deleted resource re-created from Git"

shot k20-27-self-heal-events
step "kubectl get events -n argocd --field-selector involvedObject.name=guestbook --sort-by=.lastTimestamp -o custom-columns=REASON:.reason,MESSAGE:.message | tail -6 | cut -c1-170"

shot k20-28-rollback
step "git revert --no-edit $CHANGE >/dev/null && push_main && git log -1 --oneline"
REV=$(git rev-parse HEAD)
step "wait_argo_rev $REV"
step "kubectl get deploy guestbook -n gitops-demo"
step "kubectl -n gitops-demo exec deploy/guestbook -- curl -s localhost:9898 | grep message"
step "argocd app history guestbook"
step "argocd app list | cut -c1-120"
fi

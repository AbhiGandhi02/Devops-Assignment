#!/usr/bin/env bash
# Final DevOps Project - part 4: monitoring (Prometheus, Grafana, alerts) and logs.
# Needs port-forwards: prometheus -> localhost:19090, grafana -> localhost:13000
set -u
cd "$(dirname "$0")"
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
export KUBECONFIG="$PWD/.kubeconfig"
GPASS=$(kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)
PROM=localhost:19090
DEV="-n readtrack-dev"

shot k21-33-monitoring-stack
step "helm list -n monitoring; kubectl get pods -n monitoring | awk '{print \$1, \$2, \$3}' | column -t"
step "kubectl get servicemonitor,prometheusrule -A | grep -E 'NAMESPACE|readtrack'"

shot k21-34-metrics-endpoint
step "kubectl $DEV port-forward svc/readtrack-backend 18000:8000 >/dev/null 2>&1 & sleep 2; curl -s localhost:18000/metrics | grep -E '^readtrack_' | grep -vE '_bucket|_created' | head -14; kill %1; wait 2>/dev/null"

shot k21-35-prometheus-targets
step "curl -s '$PROM/api/v1/targets?state=active' | python3 -c 'import json,sys; [print(t[\"labels\"][\"namespace\"], t[\"labels\"][\"pod\"], t[\"scrapeUrl\"], t[\"health\"]) for t in json.load(sys.stdin)[\"data\"][\"activeTargets\"] if \"readtrack\" in t[\"labels\"].get(\"job\",\"\")]' | column -t"
step "python3 monitoring/promq.py http://$PROM 'sum by (path) (rate(readtrack_http_requests_total{namespace=\"readtrack-dev\"}[5m]))'"

shot k21-36-alert-firing
step "kubectl $DEV scale deploy readtrack-backend --replicas=0 && sleep 100"
step "curl -s $PROM/api/v1/alerts | python3 -c 'import json,sys; [print(a[\"labels\"][\"alertname\"], a[\"labels\"].get(\"namespace\",\"\"), a[\"state\"], \"-\", a[\"annotations\"].get(\"summary\",\"\")) for a in json.load(sys.stdin)[\"data\"][\"alerts\"] if a[\"labels\"][\"alertname\"].startswith(\"ReadTrack\")]'"

shot k21-37-alert-resolved
step "kubectl $DEV scale deploy readtrack-backend --replicas=2 && kubectl $DEV rollout status deploy/readtrack-backend --timeout=120s && sleep 45"
step "curl -s $PROM/api/v1/alerts | python3 -c 'import json,sys; a=[x for x in json.load(sys.stdin)[\"data\"][\"alerts\"] if x[\"labels\"][\"alertname\"].startswith(\"ReadTrack\")]; print(\"ReadTrack alerts firing/pending:\", len(a))'"
step "python3 monitoring/promq.py http://$PROM 'sum(up{namespace=\"readtrack-dev\",service=\"readtrack-backend\"})'"

shot k21-38-grafana-api
step "curl -s -u admin:\$GPASS 'localhost:13000/api/search?query=ReadTrack' | python3 -c 'import json,sys; [print(d[\"uid\"], \"|\", d[\"title\"], \"|\", d[\"url\"]) for d in json.load(sys.stdin)]'"
step "curl -s -u admin:\$GPASS localhost:13000/api/dashboards/uid/readtrack-overview | python3 -c 'import json,sys; [print(\" -\", p[\"title\"]) for p in json.load(sys.stdin)[\"dashboard\"][\"panels\"]]'"

shot k21-39-logs
step "for p in /api/books /api/books/stats /api/books/42 /api/info; do curl -s -o /dev/null -w \"\$p -> %{http_code}\n\" http://readtrack-dev.localhost:8180\$p; done"
step "kubectl $DEV logs -l app.kubernetes.io/name=backend -c backend --tail=50 --prefix | grep '\"msg\": \"request\"' | tail -4"
step "kubectl $DEV logs -l app.kubernetes.io/name=backend -c backend --tail=-1 | python3 -c 'import json,sys,collections; c=collections.Counter(json.loads(l)[\"status\"] for l in sys.stdin if l.startswith(\"{\") and \"\\\"request\\\"\" in l); print(\"requests by status in the logs:\", dict(c))'"
step "kubectl get events $DEV --field-selector reason=SuccessfulRescale | cut -c1-160"

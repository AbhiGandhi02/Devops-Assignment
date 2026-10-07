#!/usr/bin/env bash
# Show alerts for my namespace from Prometheus (pending + firing) and from Alertmanager
# (what would actually be routed to Slack/email/PagerDuty).
# usage: ./alerts.sh [prometheus|alertmanager|rules]
set -euo pipefail
what=${1:-prometheus}
P=/api/v1/namespaces/monitoring/services/http:monitoring-kube-prometheus-prometheus:9090/proxy
A=/api/v1/namespaces/monitoring/services/http:monitoring-kube-prometheus-alertmanager:9093/proxy
case $what in
  rules)        url="$P/api/v1/rules?type=alert" ;;
  prometheus)   url="$P/api/v1/alerts" ;;
  alertmanager) url="$A/api/v2/alerts" ;;
  *) echo "usage: $0 [prometheus|alertmanager|rules]"; exit 1 ;;
esac
kubectl get --raw "$url" | WHAT=$what python3 -c "$(cat <<'PY'
import json, os, sys
what = os.environ["WHAT"]
data = json.load(sys.stdin)
NS = "observability"
if what == "rules":
    for g in data["data"]["groups"]:
        if f"/{NS}-" not in g["file"]:
            continue
        for r in g["rules"]:
            print(f'{g["name"]:<24} {r["name"]:<24} for={int(r["duration"])}s  state={r["state"]:<8} health={r["health"]}')
elif what == "prometheus":
    alerts = [a for a in data["data"]["alerts"] if a["labels"].get("namespace") == NS]
    if not alerts:
        print(f"  no pending/firing alerts in namespace {NS}")
    for a in alerts:
        l = a["labels"]
        who = l.get("deployment") or l.get("pod") or l.get("service") or ""
        print(f'{l["alertname"]:<24} {a["state"]:<8} {l.get("severity", ""):<8} {who:<34} since {a["activeAt"][11:19]}  value={float(a["value"]):.2f}')
else:
    alerts = [a for a in data if a["labels"].get("namespace") == NS]
    if not alerts:
        print(f"  Alertmanager has no alerts for namespace {NS}")
    for a in alerts:
        l = a["labels"]
        print(f'{l["alertname"]:<24} {a["status"]["state"]:<7} {l.get("severity", ""):<8} {a["annotations"].get("summary", "")[:80]}')
PY
)"

#!/usr/bin/env bash
# Run an instant PromQL query against Prometheus through the Kubernetes API server proxy
# (no port-forward needed) and print one line per series.
# usage: ./promql.sh '<PromQL>' [bytes|percent]
set -euo pipefail
unit=${2:-}
q=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1")
kubectl get --raw "/api/v1/namespaces/monitoring/services/http:monitoring-kube-prometheus-prometheus:9090/proxy/api/v1/query?query=$q" |
UNIT="$unit" python3 -c '
import json, os, sys
unit = os.environ["UNIT"]
res = json.load(sys.stdin)["data"]["result"]
if not res:
    print("  (no data - empty result)")
for s in sorted(res, key=lambda s: sorted(s["metric"].items())):
    labels = ", ".join(f"{k}=\"{v}\"" for k, v in sorted(s["metric"].items()) if k != "__name__")
    v = float(s["value"][1])
    if unit == "bytes":
        val = f"{v/1024/1024:9.1f} MiB"
    elif unit == "percent":
        val = f"{v:9.1f} %"
    else:
        val = f"{v:13.4f}"
    print(f"{val}   {{{labels}}}")
'

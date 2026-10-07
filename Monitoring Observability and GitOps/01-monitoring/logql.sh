#!/usr/bin/env bash
# Run a LogQL query against Loki (last N minutes) through the API server proxy.
# usage: ./logql.sh '<LogQL>' [limit] [minutes]
set -euo pipefail
limit=${2:-10}; mins=${3:-10}
start=$(( ($(date +%s) - mins*60) * 1000000000 ))
q=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1")
kubectl get --raw "/api/v1/namespaces/monitoring/services/http:loki:3100/proxy/loki/api/v1/query_range?query=$q&limit=$limit&start=$start&direction=backward" |
python3 -c '
import json, sys, datetime
data = json.load(sys.stdin)["data"]
if data["resultType"] == "streams":
    lines = []
    for st in data["result"]:
        pod = st["stream"].get("pod", "?")
        for ts, line in st["values"]:
            lines.append((int(ts), pod, line))
    for ts, pod, line in sorted(lines)[-50:]:
        t = datetime.datetime.fromtimestamp(ts / 1e9).strftime("%H:%M:%S")
        print(f"{t} {pod:<34} {line[:150]}")
else:  # metric query, e.g. count_over_time / rate
    for s in data["result"]:
        labels = ", ".join(f"{k}=\"{v}\"" for k, v in sorted(s["metric"].items()))
        val = float(s["values"][-1][1])
        print(f"{val:10.0f}   {{{labels}}}")
'

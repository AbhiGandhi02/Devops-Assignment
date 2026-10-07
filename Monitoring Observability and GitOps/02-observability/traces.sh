#!/usr/bin/env bash
# Query the Jaeger API through the API server proxy.
# usage: ./traces.sh services
#        ./traces.sh latest <service> [operation]   -> print the newest trace as a span tree
#        ./traces.sh trace <traceID>                  -> print one trace (e.g. a trace_id copied from a log line)
set -euo pipefail
J=/api/v1/namespaces/observability/services/http:jaeger:16686/proxy/api
case ${1:-services} in
  services)
    kubectl get --raw "$J/services" | python3 -c 'import json,sys; [print(s) for s in json.load(sys.stdin)["data"]]' ;;
  latest|trace)
    if [ "$1" = trace ]; then
      url="$J/traces/$2"
    else
      svc=$2; op=${3:-}
      url="$J/traces?service=$svc&limit=20&lookback=5m"
      [ -n "$op" ] && url="$url&operation=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$op")"
    fi
    kubectl get --raw "$url" | python3 -c "$(cat <<'PY'
import json, sys
traces = json.load(sys.stdin)["data"]
# the newest complete trace (most spans, then newest) - very fresh traces may still
# be missing spans that the other service has not flushed yet
traces.sort(key=lambda t: (len(t["spans"]), max(s["startTime"] for s in t["spans"])), reverse=True)
t = traces[0]
procs = {k: v["serviceName"] for k, v in t["processes"].items()}
spans = {s["spanID"]: s for s in t["spans"]}
children = {}
roots = []
for s in t["spans"]:
    parent = next((r["spanID"] for r in s.get("references", []) if r["refType"] == "CHILD_OF" and r["spanID"] in spans), None)
    (children.setdefault(parent, []) if parent else roots).append(s)
t0 = min(s["startTime"] for s in t["spans"])
print(f'traceID {t["traceID"]}  spans={len(t["spans"])}  services={sorted(set(procs.values()))}')
def show(s, depth):
    tags = {x["key"]: x["value"] for x in s["tags"]}
    status = tags.get("http.response.status_code", tags.get("http.status_code", ""))
    print(f'{"  " * depth}{procs[s["processID"]]:<17} {s["operationName"]:<28} start=+{(s["startTime"]-t0)/1000:7.2f}ms  dur={s["duration"]/1000:7.2f}ms  {status}')
    for c in sorted(children.get(s["spanID"], []), key=lambda c: c["startTime"]):
        show(c, depth + 1)
for r in roots:
    show(r, 0)
PY
)" ;;
esac

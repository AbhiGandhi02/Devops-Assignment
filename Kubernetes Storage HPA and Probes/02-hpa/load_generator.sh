#!/usr/bin/env bash
# Start / stop the in-cluster load generator.
#   ./load_generator.sh start [replicas]   (default 3)
#   ./load_generator.sh stop
set -euo pipefail
cd "$(dirname "$0")"
case "${1:-start}" in
  start)
    kubectl apply -f load-generator.yaml
    kubectl scale deployment load-generator -n hpa-lab --replicas="${2:-3}"
    echo "Load running. Watch it with: kubectl get hpa -n hpa-lab -w" ;;
  stop)
    kubectl delete -f load-generator.yaml --ignore-not-found ;;
  *) echo "usage: $0 start [replicas] | stop"; exit 1 ;;
esac

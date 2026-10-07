#!/usr/bin/env bash
# Installs Prometheus + Grafana + Alertmanager (kube-prometheus-stack) and the ReadTrack dashboard.
set -euo pipefail
cd "$(dirname "$0")"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community >/dev/null
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
# Grafana admin password generated at install time, stored only in the cluster
if ! kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
  kubectl -n monitoring create secret generic grafana-admin \
    --from-literal=admin-user=admin --from-literal=admin-password="$(openssl rand -hex 12)"
fi
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring -f kube-prometheus-stack-values.yaml --wait --timeout 10m
kubectl apply -f grafana-dashboard-readtrack.yaml

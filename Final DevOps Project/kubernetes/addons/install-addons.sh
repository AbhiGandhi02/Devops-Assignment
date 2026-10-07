#!/usr/bin/env bash
# Cluster add-ons the app relies on: ingress-nginx (Ingress) and metrics-server (HPA).
set -euo pipefail
INGRESS_URL=https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.13.3/deploy/static/provider/kind/deploy.yaml
METRICS_URL=https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.8.0/components.yaml

kubectl apply -f "$INGRESS_URL"
# the controller uses hostPort 80/443, which kind maps to the host only on the control-plane
# (labelled ingress-ready=true) - pin it there, otherwise it lands on the worker and gets no traffic
kubectl -n ingress-nginx patch deployment ingress-nginx-controller --type=merge \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"ingress-ready":"true","kubernetes.io/os":"linux"}}}}}'
kubectl apply -f "$METRICS_URL"
# kind kubelets use self-signed serving certs -> metrics-server must skip TLS verification
if ! kubectl -n kube-system get deploy metrics-server -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q insecure-tls; then
  kubectl -n kube-system patch deployment metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
fi

kubectl -n ingress-nginx wait --for=condition=Available deployment/ingress-nginx-controller --timeout=240s
kubectl -n kube-system rollout status deployment/metrics-server --timeout=240s

#!/usr/bin/env bash
# Kubernetes Fundamentals - replays every command in this section's README.
# Usage:  kind create cluster --config kind-cluster.yaml && ./run-labs.sh
# Every command is echoed before it runs, so the output is a real transcript.
set -u
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }

CP=abhi-devops-control-plane
WK=abhi-devops-worker

shot k8s-01-cluster-info
step "kubectl version"
step "kubectl cluster-info"
step "kubectl get nodes -o wide"
step "kubectl get namespaces"

shot k8s-02-control-plane-pods
step "kubectl get pods -n kube-system -o wide"

shot k8s-03-node-capacity
step "kubectl describe node $WK | sed -n '/^Capacity/,/^System Info/p'"
step "kubectl api-resources | head -12"

shot k8s-04-first-pod
step "kubectl run hello-abhi --image=nginx:1.25-alpine --port=80"
step "kubectl wait --for=condition=Ready pod/hello-abhi --timeout=120s"
step "kubectl get pod hello-abhi -o wide"
step "kubectl describe pod hello-abhi | sed -n '/^Events/,\$p'"
step "kubectl exec hello-abhi -- nginx -v"
step "kubectl logs hello-abhi | tail -3"

shot k8s-05-namespaces
step "kubectl create namespace abhi-dev"
step "kubectl run hello-abhi --image=nginx:1.25-alpine -n abhi-dev"
step "kubectl get pods -A | grep -E 'NAMESPACE|hello-abhi'"

shot k8s-06-dryrun-explain
step "kubectl run scratch --image=nginx --dry-run=client -o yaml"
step "kubectl explain pod.spec.containers.image"

shot k8s-07-cleanup
step "kubectl delete pod hello-abhi --wait=false"
step "kubectl delete namespace abhi-dev --wait=false"

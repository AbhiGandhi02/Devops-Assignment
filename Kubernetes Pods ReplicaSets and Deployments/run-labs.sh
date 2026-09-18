#!/usr/bin/env bash
# Kubernetes Pods, ReplicaSets & Deployments - replays this section's README.
# Assumes the abhi-devops kind cluster from ../Kubernetes Fundamentals is running.
set -u
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
M=manifests

shot k9-01-bare-pod
step "kubectl apply -f $M/nginx-pod.yaml"
step "kubectl wait --for=condition=Ready pod/orbit-demo-pod --timeout=180s"
step "kubectl get pod orbit-demo-pod -o wide --show-labels"
step "kubectl delete pod orbit-demo-pod"
step "kubectl get pods"

shot k9-02-replicaset
step "kubectl apply -f $M/backend-rs.yaml"
step "kubectl wait --for=condition=Ready pod -l app=orbit-api --timeout=300s"
step "kubectl get rs,pods -l app=orbit-api -o wide"
VICTIM=$(kubectl get pods -l app=orbit-api -o jsonpath='{.items[0].metadata.name}')
step "kubectl delete pod $VICTIM --wait=false"
step "kubectl get pods -l app=orbit-api"
step "kubectl scale rs orbit-api-rs --replicas=5"
step "kubectl get rs orbit-api-rs"
step "kubectl describe rs orbit-api-rs | sed -n '/^Events/,\$p'"
step "kubectl delete rs orbit-api-rs"

shot k9-03-deployment-v1
step "kubectl apply -f $M/deployment-v1.yaml"
step "kubectl rollout status deployment/orbit-api --timeout=300s"
step "kubectl get deploy,rs,pods -l app=orbit-api"

shot k9-04-rolling-update
step "kubectl apply -f $M/deployment-v2.yaml"
step "kubectl annotate deployment/orbit-api kubernetes.io/change-cause='Upgrade to release 2.0.0' --overwrite"
step "kubectl rollout status deployment/orbit-api --timeout=300s"
step "kubectl get rs -l app=orbit-api"
step "kubectl get pods -l app=orbit-api -L release"
step "kubectl rollout history deployment/orbit-api"

shot k9-05-rollback
step "kubectl rollout undo deployment/orbit-api"
step "kubectl rollout status deployment/orbit-api --timeout=300s | tail -1"
step "kubectl get rs -l app=orbit-api"
step "kubectl rollout history deployment/orbit-api"
step "kubectl scale deployment orbit-api --replicas=5"
step "kubectl rollout status deployment/orbit-api --timeout=300s | tail -1"
step "kubectl get deploy orbit-api"

shot k9-06-broken-image
step "kubectl set image deployment/orbit-api api-server=orbit-api:no-such-tag-v999"
sleep 25
step "kubectl get pods -l app=orbit-api"
step "kubectl describe pod \$(kubectl get pods -l app=orbit-api --no-headers | grep -E 'ImagePull|ErrImage' | head -1 | cut -d' ' -f1) | grep -E 'Failed|Back-off' | head -3"
step "kubectl rollout undo deployment/orbit-api"
step "kubectl rollout status deployment/orbit-api --timeout=300s | tail -1"
step "kubectl delete deployment orbit-api"

shot k9-07-daemonset
step "kubectl apply -f $M/node-agent-ds.yaml"
step "kubectl rollout status ds/host-metrics-agent --timeout=300s"
step "kubectl get ds host-metrics-agent"
step "kubectl get pods -l app=host-metrics-agent -o wide"
step "kubectl logs -l app=host-metrics-agent --tail=2"
step "kubectl describe node abhi-devops-control-plane | grep Taints"
step "kubectl delete ds host-metrics-agent"

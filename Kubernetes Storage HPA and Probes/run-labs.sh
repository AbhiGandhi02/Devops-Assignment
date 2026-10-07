#!/usr/bin/env bash
# Kubernetes Storage, HPA & Probes - replays every command in this section's README.
# Assumes the abhi-devops kind cluster from ../Kubernetes Fundamentals is running.
set -u
cd "$(dirname "$0")"
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
V=01-kubernetes-volumes/manifests
H=02-hpa
M=03-mini-project
# watch a resource in the background for N seconds and keep the output
watch_for() { # seconds outfile cmd...
  local secs=$1 out=$2; shift 2
  "$@" > "$out" 2>&1 & local pid=$!
  sleep "$secs"; kill $pid 2>/dev/null; wait $pid 2>/dev/null
}

# ---------------- Task 0: metrics-server ----------------
shot k13-01-metrics-server
step "kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.8.0/components.yaml | tail -3"
# kind kubelets use self-signed certs, so metrics-server must skip TLS verification
step "kubectl patch deployment metrics-server -n kube-system --type=json -p '[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--kubelet-insecure-tls\"}]'"
step "kubectl rollout status deployment/metrics-server -n kube-system --timeout=180s | tail -1"
until kubectl top nodes >/dev/null 2>&1; do sleep 5; done
step "kubectl top nodes"

# ---------------- Task 1: volumes ----------------
step "kubectl create namespace storage-lab"

shot k13-02-emptydir
step "kubectl apply -f $V/01-emptydir-pod.yaml"
kubectl wait -n storage-lab --for=condition=Ready pod/emptydir-demo --timeout=120s >/dev/null; sleep 6
step "kubectl exec -n storage-lab emptydir-demo -c reader -- tail -3 /shared/log.txt"
step "kubectl get pod emptydir-demo -n storage-lab -o jsonpath='{.metadata.uid}{\"\\n\"}'"
step "kubectl delete pod emptydir-demo -n storage-lab --now"
step "kubectl apply -f $V/01-emptydir-pod.yaml"
kubectl wait -n storage-lab --for=condition=Ready pod/emptydir-demo --timeout=120s >/dev/null
step "kubectl exec -n storage-lab emptydir-demo -c reader -- cat /shared/log.txt    # new Pod -> brand new, empty volume"

shot k13-03-hostpath
step "kubectl apply -f $V/02-hostpath-pod.yaml"
kubectl wait -n storage-lab --for=condition=Ready pod/hostpath-demo --timeout=120s >/dev/null
step "kubectl delete pod hostpath-demo -n storage-lab --now"
step "kubectl apply -f $V/02-hostpath-pod.yaml"
kubectl wait -n storage-lab --for=condition=Ready pod/hostpath-demo --timeout=120s >/dev/null
step "kubectl exec -n storage-lab hostpath-demo -- cat /node-data/visits.txt"
step "docker exec abhi-devops-worker cat /tmp/abhi-hostpath-demo/visits.txt    # the file lives on the node itself"

shot k13-04-static-pv-pvc
step "kubectl apply -f $V/03-pv-static.yaml"
step "kubectl get pv abhi-manual-pv"
step "kubectl apply -f $V/04-pvc-static.yaml"
sleep 2
step "kubectl get pv abhi-manual-pv"
step "kubectl get pvc manual-claim -n storage-lab"
step "kubectl apply -f $V/05-pod-with-pvc.yaml"
kubectl wait -n storage-lab --for=condition=Ready pod/pvc-demo --timeout=120s >/dev/null
step "kubectl delete pod pvc-demo -n storage-lab --now"
step "kubectl apply -f $V/05-pod-with-pvc.yaml"
kubectl wait -n storage-lab --for=condition=Ready pod/pvc-demo --timeout=120s >/dev/null
step "kubectl exec -n storage-lab pvc-demo -- cat /data/orders.txt     # two lines = data survived the Pod"

shot k13-05-storageclass-dynamic
step "kubectl apply -f $V/06-storageclass.yaml"
step "kubectl get storageclass"
step "kubectl apply -f $V/07-pvc-dynamic.yaml"
step "kubectl get pvc dynamic-claim -n storage-lab     # WaitForFirstConsumer: Pending until the Pod is scheduled"
kubectl wait -n storage-lab --for=condition=Ready pod/dynamic-demo --timeout=180s >/dev/null
step "kubectl get pvc dynamic-claim -n storage-lab"
step "kubectl get pv | grep -E 'NAME|dynamic-claim'"
step "kubectl logs dynamic-demo -n storage-lab"

shot k13-06-reclaim-policy
step "kubectl delete namespace storage-lab"
step "kubectl get pv     # dynamic PV (Delete) is gone, manual PV (Retain) is Released"
step "kubectl delete pv abhi-manual-pv"
step "kubectl delete storageclass abhi-fast"

# ---------------- Task 2: HPA ----------------
step "kubectl create namespace hpa-lab"
shot k13-07-hpa-setup
step "kubectl apply -f $H/deployment.yaml"
step "kubectl rollout status deployment/orbit-web -n hpa-lab --timeout=120s | tail -1"
step "kubectl apply -f $H/hpa.yml"
sleep 45
step "kubectl get hpa -n hpa-lab"
step "kubectl top pods -n hpa-lab"

shot k13-08-hpa-load
step "./$H/load_generator.sh start 3"
watch_for 150 /tmp/hpa-watch.txt kubectl get hpa orbit-web-hpa -n hpa-lab --watch
step "cat /tmp/hpa-watch.txt     # kubectl get hpa -w, ~2.5 minutes under load"
step "kubectl top pods -n hpa-lab -l app=orbit-web"
step "kubectl get pods -n hpa-lab -l app=orbit-web"

shot k13-09-hpa-describe
step "kubectl describe hpa orbit-web-hpa -n hpa-lab | sed -n '/^Metrics/,\$p'"

shot k13-10-hpa-scale-down
step "./$H/load_generator.sh stop"
watch_for 150 /tmp/hpa-down.txt kubectl get hpa orbit-web-hpa -n hpa-lab --watch
step "cat /tmp/hpa-down.txt     # load stopped -> replicas fall back after the 60s stabilization window"
step "kubectl get pods -n hpa-lab -l app=orbit-web"
step "kubectl delete namespace hpa-lab"

# ---------------- Task 3: mini project ----------------
shot k13-11-mini-deploy
step "kubectl apply -f $M/namespace.yaml"
step "kubectl apply -f $M/pvc.yaml"
step "kubectl get pvc -n production-webapp"
step "kubectl apply -f $M/deployment.yaml -f $M/service.yaml -f $M/hpa.yaml"
step "kubectl rollout status deployment/web-app -n production-webapp --timeout=180s | tail -1"
step "kubectl get pvc,pods,svc -n production-webapp -o wide"
sleep 40
step "kubectl get hpa -n production-webapp"

shot k13-12-mini-persistence
POD=$(kubectl get pods -n production-webapp -l app=web-app -o jsonpath='{.items[0].metadata.name}')
step "kubectl exec -n production-webapp $POD -- sh -c 'echo \"Student: Abhi Gandhi (24bcs10397)\" > /data/student.txt'"
step "kubectl exec -n production-webapp $POD -- cat /data/student.txt"
step "kubectl delete pod -n production-webapp $POD"
step "kubectl rollout status deployment/web-app -n production-webapp --timeout=120s | tail -1"
NEW=$(kubectl get pods -n production-webapp -l app=web-app --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
step "kubectl get pods -n production-webapp -l app=web-app"
step "kubectl exec -n production-webapp $NEW -- cat /data/student.txt     # read from the NEW Pod"

shot k13-13-mini-service-probes
kubectl port-forward -n production-webapp svc/web-service 8089:80 >/dev/null 2>&1 & PF=$!
sleep 3
step "curl -s http://localhost:8089 | grep -o '<title>.*</title>'"
kill $PF; wait $PF 2>/dev/null
step "kubectl describe pod -n production-webapp $NEW | grep -E 'Liveness|Readiness|Startup'"
step "kubectl get endpointslices -n production-webapp -l kubernetes.io/service-name=web-service -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{\"  \"}{.addresses[0]}{\"  ready=\"}{.conditions.ready}{\"\\n\"}{end}'"

shot k13-14-mini-hpa
step "kubectl run load-generator -n production-webapp --image=busybox:1.36 --restart=Never -- /bin/sh -c 'while true; do wget -q -O- http://web-service >/dev/null; done'"
step "kubectl run load-generator-2 -n production-webapp --image=busybox:1.36 --restart=Never -- /bin/sh -c 'while true; do wget -q -O- http://web-service >/dev/null; done'"
watch_for 150 /tmp/mini-hpa.txt kubectl get hpa web-app-hpa -n production-webapp --watch
step "cat /tmp/mini-hpa.txt"
step "kubectl get pods -n production-webapp -l app=web-app"
step "kubectl delete pod load-generator load-generator-2 -n production-webapp --now"

shot k13-15-mini-readiness-gate
# Bonus challenge 2: break the readiness probe -> Pods stay Running but leave the Service
step "kubectl patch deployment web-app -n production-webapp --type=json -p '[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/readinessProbe/httpGet/path\",\"value\":\"/does-not-exist\"}]'"
sleep 40
step "kubectl get pods -n production-webapp -l app=web-app"
step "kubectl get endpointslices -n production-webapp -l kubernetes.io/service-name=web-service -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{\"  \"}{.addresses[0]}{\"  ready=\"}{.conditions.ready}{\"\\n\"}{end}'"
step "kubectl rollout undo deployment/web-app -n production-webapp"
step "kubectl rollout status deployment/web-app -n production-webapp --timeout=180s | tail -1"
step "kubectl get endpointslices -n production-webapp -l kubernetes.io/service-name=web-service -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{\"  \"}{.addresses[0]}{\"  ready=\"}{.conditions.ready}{\"\\n\"}{end}'"

shot k13-16-cleanup
step "kubectl delete namespace production-webapp"
step "kubectl get pv"

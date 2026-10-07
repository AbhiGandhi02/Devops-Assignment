#!/usr/bin/env bash
# Final DevOps Project - part 2: plain Kubernetes manifests, Helm, Ingress, HPA, storage, NetworkPolicy.
set -u
cd "$(dirname "$0")"
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
export KUBECONFIG="$PWD/.kubeconfig"
# two images built and pushed by the pipeline (commit SHAs)
A=060be798b4caa5007d7ea4429f31c0304a9a0ce7
B=${B:-178914b}
B=$(git rev-parse "$B")
DEV="-n readtrack-dev"

# ------------------------------------------------------------------ plain manifests (kubectl + kustomize)
shot k21-13-k8s-apply
step "kubectl apply -f kubernetes/namespace.yaml"
step "kubectl -n readtrack get secret readtrack-db >/dev/null 2>&1 || kubectl -n readtrack create secret generic readtrack-db --from-literal=postgres-password=\"\$(openssl rand -hex 16)\""
step "kubectl apply -k kubernetes/"
step "kubectl -n readtrack rollout status deploy/readtrack-backend --timeout=180s && kubectl -n readtrack rollout status deploy/readtrack-frontend --timeout=120s"

shot k21-14-k8s-resources
step "kubectl get deploy,sts,svc,ingress,hpa,pvc -n readtrack"
step "sleep 15; kubectl get pods -n readtrack -o wide | awk '{print \$1, \$2, \$3, \$4, \$7}' | column -t"

shot k21-15-configmap-secret
step "kubectl -n readtrack get configmap readtrack-config -o jsonpath='{.data}'; echo"
step "kubectl -n readtrack get secret readtrack-db -o jsonpath='{.type} keys={.data}' | sed -E 's/\"postgres-password\":\"[^\"]+\"/\"postgres-password\":\"<base64, hidden>\"/'; echo"
step "kubectl -n readtrack exec deploy/readtrack-backend -c backend -- sh -c 'env | grep -E \"^(APP_ENV|DB_HOST|DB_NAME|DB_USER|WELCOME_MESSAGE)=\" | sort; echo DATABASE_URL=\${DATABASE_URL%%:*}://\${DB_USER}:*****@\${DB_HOST}:5432/\${DB_NAME}'"

shot k21-16-probes
step "P=\$(kubectl -n readtrack get pod -l app.kubernetes.io/name=backend -o jsonpath='{.items[0].metadata.name}'); echo pod: \$P; kubectl -n readtrack describe pod \$P | grep -E 'Liveness|Readiness|Startup'"
step "kubectl -n readtrack get pod \$P -o jsonpath='init: {.spec.initContainers[0].name} -> {.spec.initContainers[0].command[2]}{\"\\n\"}requests: {.spec.containers[0].resources.requests}  limits: {.spec.containers[0].resources.limits}{\"\\n\"}'"
step "kubectl -n readtrack logs \$P -c migrate"

shot k21-17-storage-persistence
step "curl -s -X POST http://readtrack-k8s.localhost:8180/api/books -H 'Content-Type: application/json' -d '{\"title\":\"Kubernetes Up and Running\",\"author\":\"Burns, Beda, Hightower\",\"status\":\"reading\",\"pages\":326}' | cut -c1-110"
step "kubectl -n readtrack delete pod readtrack-postgres-0 && kubectl -n readtrack wait --for=condition=Ready pod/readtrack-postgres-0 --timeout=120s"
step "sleep 6; curl -s http://readtrack-k8s.localhost:8180/api/books | python3 -c 'import json,sys; [print(b[\"id\"], b[\"title\"], \"-\", b[\"status\"]) for b in json.load(sys.stdin)]'"
step "kubectl get pv | grep readtrack/ | awk '{print \$1, \$2, \$5, \$6, \$7}' | column -t"

# ------------------------------------------------------------------ Helm
shot k21-18-helm-install
step "helm lint helm/readtrack -f helm/readtrack/values-dev.yaml --set database.existingSecret=readtrack-db | tail -2"
step "helm uninstall readtrack $DEV --wait >/dev/null 2>&1; kubectl $DEV delete pvc --all --wait >/dev/null 2>&1; kubectl $DEV get secret readtrack-db >/dev/null 2>&1 || kubectl $DEV create secret generic readtrack-db --from-literal=postgres-password=\"\$(openssl rand -hex 16)\""
step "helm upgrade --install readtrack helm/readtrack $DEV -f helm/readtrack/values-dev.yaml --set image.tag=$A --set database.existingSecret=readtrack-db --wait --timeout 5m | head -9"

shot k21-19-helm-resources
step "sleep 20; helm list $DEV"
step "kubectl get pods,svc,ingress,hpa,pdb,networkpolicy $DEV"

shot k21-20-helm-upgrade-rollback
step "helm upgrade readtrack helm/readtrack $DEV -f helm/readtrack/values-dev.yaml --set image.tag=$B --set database.existingSecret=readtrack-db --set config.welcomeMessage='Dev - upgraded by helm upgrade' --wait --timeout 5m | grep -E 'STATUS|REVISION'"
step "curl -s http://readtrack-dev.localhost:8180/api/info; echo"
step "helm rollback readtrack 1 $DEV --wait --timeout 5m && helm history readtrack $DEV --max 5"
step "kubectl $DEV rollout status deploy/readtrack-backend --timeout=120s >/dev/null; sleep 3; curl -s http://readtrack-dev.localhost:8180/api/info; echo"

shot k21-21-helm-test
step "helm test readtrack $DEV --logs | grep -vE '^$|TEST SUITE|Last Started|Last Completed'"

shot k21-22-ingress
step "kubectl get ingress -A | awk '{print \$1, \$2, \$3, \$4, \$6}' | column -t"
step "curl -s -o /dev/null -w 'GET /         -> %{http_code} (%{content_type})\n' http://readtrack-dev.localhost:8180/"
step "curl -s -X POST http://readtrack-dev.localhost:8180/api/books -H 'Content-Type: application/json' -d '{\"title\":\"The DevOps Handbook\",\"author\":\"Kim, Humble, Debois, Willis\",\"status\":\"finished\",\"pages\":480,\"rating\":5}' | cut -c1-120; echo"
step "curl -s http://readtrack-dev.localhost:8180/api/books/stats; echo"
step "curl -s -o /dev/null -w 'unknown host -> %{http_code}\n' http://nothing-here.localhost:8180/"

# ------------------------------------------------------------------ HPA
shot k21-23-hpa-scaling
step "kubectl get hpa $DEV"
step "ab -q -k -c 40 -t 75 -H 'Host: readtrack-dev.localhost' http://127.0.0.1:8180/api/books/stats 2>&1 | grep -E 'Complete requests|Failed requests|Requests per second'"
step "kubectl get hpa $DEV; kubectl top pods $DEV -l app.kubernetes.io/name=backend"
step "kubectl $DEV describe hpa readtrack-backend | grep -E 'SuccessfulRescale' | tail -3"

shot k21-24-networkpolicy
step "kubectl $DEV get networkpolicy readtrack-postgres-allow-backend -o jsonpath='{.spec}'; echo"
step "kubectl $DEV exec deploy/readtrack-frontend -- sh -c 'nc -zv -w 3 readtrack-postgres 5432 2>&1 || echo \"frontend -> postgres:5432 BLOCKED\"'"
step "kubectl $DEV exec deploy/readtrack-backend -c backend -- python -c \"import socket; socket.create_connection(('readtrack-postgres', 5432), 3); print('backend  -> postgres:5432 connected')\""

shot k21-25-pod-security
step "kubectl get ns -L pod-security.kubernetes.io/enforce | grep -E 'NAME|readtrack'"
step "kubectl $DEV run root-test --image=busybox:1.36 --restart=Never -- id 2>&1 | head -3"

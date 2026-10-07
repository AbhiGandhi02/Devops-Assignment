#!/usr/bin/env bash
# Final troubleshooting challenge: deploy ReadTrack with 8 injected bugs into readtrack-ts,
# then find and fix them one by one - symptom -> investigation -> root cause -> fix -> verify.
set -u
cd "$(dirname "$0")/.."
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
export KUBECONFIG="$PWD/.kubeconfig"
TS="-n readtrack-ts"
GOOD=060be798b4caa5007d7ea4429f31c0304a9a0ce7
URL=http://readtrack-ts.localhost:8180

# clean slate (quiet)
kubectl delete -k troubleshooting/broken --ignore-not-found --wait >/dev/null 2>&1
kubectl $TS delete pvc --all --wait >/dev/null 2>&1
kubectl $TS delete secret readtrack-db --ignore-not-found >/dev/null 2>&1

shot k21-45-ts-broken-deploy
step "kubectl $TS create secret generic readtrack-db --from-literal=password=\"\$(openssl rand -hex 16)\""
step "kubectl apply -k troubleshooting/broken"
step "sleep 45; kubectl get pods,pvc,hpa $TS"
step "curl -s -o /dev/null -w 'GET /           -> %{http_code}\n' $URL/; curl -s -o /dev/null -w 'GET /api/info   -> %{http_code}\n' $URL/api/info"

# ---------------------------------------------------------------- issue 1: PVC pending
shot k21-46-ts-1-pvc-pending
step "kubectl $TS describe pod readtrack-postgres-0 | grep -A3 '^Events' | tail -2"
step "kubectl $TS describe pvc data-readtrack-postgres-0 | grep -E 'StorageClass|Status|Warning' | head -4"
step "kubectl get storageclass"
step "kubectl $TS delete statefulset readtrack-postgres && kubectl $TS delete pvc data-readtrack-postgres-0"
step "kubectl kustomize troubleshooting/broken | sed '/storageClassName: fast-ssd/d' | kubectl apply -f - --selector='app.kubernetes.io/part-of=readtrack' 2>&1 | grep statefulset"
step "sleep 10; kubectl $TS get pvc; kubectl $TS get pod readtrack-postgres-0"

# ---------------------------------------------------------------- issue 2: missing Secret key
shot k21-47-ts-2-secret-key
step "kubectl $TS describe pod readtrack-postgres-0 | grep -E 'Warning|Error' | tail -2 | cut -c1-170"
step "kubectl $TS get secret readtrack-db -o jsonpath='{.data}' | sed -E 's/:\"[^\"]+\"/:\"<hidden>\"/'; echo"
step "kubectl $TS create secret generic readtrack-db --from-literal=postgres-password=\"\$(openssl rand -hex 16)\" --dry-run=client -o yaml | kubectl apply -f -"
step "kubectl $TS delete pod readtrack-postgres-0 && kubectl $TS wait --for=condition=Ready pod/readtrack-postgres-0 --timeout=120s"

# ---------------------------------------------------------------- issue 3: wrong image tag
shot k21-48-ts-3-image-tag
step "kubectl $TS get pods -l app.kubernetes.io/name=backend"
step "kubectl $TS get events --field-selector reason=Failed -o custom-columns=OBJECT:.involvedObject.name,MESSAGE:.message | grep -i 'failed to pull' | head -1 | fold -w 140"
step "docker manifest inspect ghcr.io/abhigandhi02/readtrack-backend:v1.0-relase >/dev/null 2>&1 && echo tag exists || echo 'tag v1.0-relase does NOT exist in GHCR'"
step "kubectl $TS set image deploy/readtrack-backend migrate=ghcr.io/abhigandhi02/readtrack-backend:$GOOD backend=ghcr.io/abhigandhi02/readtrack-backend:$GOOD"
step "sleep 40; kubectl $TS get pods -l app.kubernetes.io/name=backend"

# ---------------------------------------------------------------- issue 4: readiness probe path
shot k21-49-ts-4-readiness-probe
step "NEW=\$(kubectl $TS get pod -l app.kubernetes.io/name=backend --sort-by=.metadata.creationTimestamp -o name | tail -1); kubectl $TS describe \$NEW | grep -E 'Ready:|Readiness' | head -3; kubectl $TS describe \$NEW | grep 'Readiness probe failed' | tail -1 | cut -c1-160"
step "kubectl $TS logs deploy/readtrack-backend -c backend --tail=50 | grep '/readyz' | tail -2; kubectl $TS exec deploy/readtrack-backend -c backend -- python -c \"import urllib.request as u; print('but /ready ->', u.urlopen('http://127.0.0.1:8000/ready').status)\""
step "kubectl $TS get endpoints readtrack-backend"
step "kubectl $TS patch deploy readtrack-backend --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/readinessProbe/httpGet/path\",\"value\":\"/ready\"}]'"
step "kubectl $TS rollout status deploy/readtrack-backend --timeout=180s | tail -1; kubectl $TS get endpoints readtrack-backend"

# ---------------------------------------------------------------- issue 5: Service targetPort
shot k21-50-ts-5-service-port
step "kubectl $TS exec deploy/readtrack-frontend -- wget -qO- -T 3 http://readtrack-backend:8000/health"
step "kubectl $TS get svc readtrack-backend -o jsonpath='service port {.spec.ports[0].port} -> targetPort {.spec.ports[0].targetPort}{\"\\n\"}'; kubectl $TS get endpoints readtrack-backend -o jsonpath='endpoints: {.subsets[0].addresses[*].ip} port {.subsets[0].ports[0].port}{\"\\n\"}'; kubectl $TS get deploy readtrack-backend -o jsonpath='container listens on {.spec.template.spec.containers[0].ports[0].containerPort}{\"\\n\"}'"
step "kubectl $TS patch svc readtrack-backend --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/ports/0/targetPort\",\"value\":\"http\"}]'"
step "kubectl $TS get endpoints readtrack-backend"

# ---------------------------------------------------------------- issue 6: Ingress wrong backend
shot k21-51-ts-6-ingress-backend
step "curl -s -o /dev/null -w 'GET /api/info -> %{http_code}\n' $URL/api/info"
step "kubectl $TS describe ingress readtrack | grep -E '/api|/ ' "
step "kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=300 | grep -E 'readtrack-api' | tail -1 | cut -c1-170"
step "kubectl $TS patch ingress readtrack --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/rules/0/http/paths/0/backend/service/name\",\"value\":\"readtrack-backend\"}]'"
step "sleep 3; curl -s $URL/api/info; echo"

# ---------------------------------------------------------------- issue 7: Service selector
shot k21-52-ts-7-service-selector
step "curl -s -o /dev/null -w 'GET / -> %{http_code}\n' $URL/"
step "kubectl $TS get endpoints readtrack-frontend; kubectl $TS get svc readtrack-frontend -o jsonpath='selector: {.spec.selector}{\"\\n\"}'"
step "kubectl $TS get pods -l app.kubernetes.io/name=frontend --show-labels | awk '{print \$1, \$6}' | column -t"
step "kubectl $TS patch svc readtrack-frontend --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/selector/app.kubernetes.io~1name\",\"value\":\"frontend\"}]'"
step "kubectl $TS get endpoints readtrack-frontend; sleep 3; curl -s -o /dev/null -w 'GET / -> %{http_code}\n' $URL/"

# ---------------------------------------------------------------- issue 8: HPA without requests
shot k21-53-ts-8-hpa-requests
step "kubectl $TS get hpa readtrack-backend"
step "kubectl $TS get events --field-selector reason=FailedGetResourceMetric -o custom-columns=MESSAGE:.message | grep -E 'MESSAGE|missing request' | sort -u | cut -c1-150"
step "kubectl $TS get deploy readtrack-backend -o jsonpath='backend resources: {.spec.template.spec.containers[0].resources}{\"\\n\"}'"
step "kubectl $TS set resources deploy readtrack-backend -c backend --requests=cpu=50m,memory=96Mi --limits=cpu=500m,memory=256Mi"
step "kubectl $TS rollout status deploy/readtrack-backend --timeout=180s | tail -1; sleep 60; kubectl $TS get hpa readtrack-backend"

# ---------------------------------------------------------------- final verification
shot k21-54-ts-verified
step "kubectl get pods,svc,ingress,hpa,pvc $TS"
step "curl -s -X POST $URL/api/books -H 'Content-Type: application/json' -d '{\"title\":\"Release It!\",\"author\":\"Michael Nygard\",\"status\":\"finished\",\"pages\":376,\"rating\":5}' | cut -c1-90; echo; curl -s $URL/api/books/stats; echo"
step "kubectl diff -k troubleshooting/fixed >/dev/null && echo 'live state == troubleshooting/fixed (no diff)' || kubectl diff -k troubleshooting/fixed | grep -E '^[-+] ' | grep -vE 'generation|resourceVersion|uid|creationTimestamp|last-applied|deprecated.daemonset|kubectl.kubernetes.io/restartedAt' | head -10"

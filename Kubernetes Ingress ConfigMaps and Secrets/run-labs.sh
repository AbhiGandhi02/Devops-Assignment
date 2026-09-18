#!/usr/bin/env bash
# Kubernetes Ingress, ConfigMaps & Secrets - replays this section's README.
# Assumes the abhi-devops kind cluster from ../Kubernetes Fundamentals is running,
# because this section needs the control-plane node's port 80 published on 8088.
set -u
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
M=manifests
ING=https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.13.3/deploy/static/provider/kind/deploy.yaml

# ------------------------------------------------- 0. the Ingress controller
shot k11-01-ingress-controller
step "kubectl apply -f $ING | tail -6"
step "kubectl -n ingress-nginx patch deploy ingress-nginx-controller --type merge -p '{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"kubernetes.io/os\":\"linux\",\"ingress-ready\":\"true\"}}}}}'"
step "kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s"
step "kubectl get pods -n ingress-nginx -o wide"
step "kubectl get ingressclass"

# ------------------------------------------------------------- 1. ConfigMap
shot k11-02-configmap
step "kubectl apply -f $M/configmap.yaml"
step "kubectl get configmap bazaar-app-config"
step "kubectl describe configmap bazaar-app-config | sed -n '/^Data/,/^BinaryData/p'"
step "kubectl create configmap bazaar-cli-config --from-literal=FEATURE_TOGGLE=true --from-literal=DEPLOY_REGION=ap-south-1"
step "kubectl get configmap bazaar-cli-config -o jsonpath='{.data}'; echo"

# ---------------------------------------------------------------- 2. Secret
shot k11-03-secret
step "kubectl apply -f $M/secret.yaml"
step "kubectl get secret bazaar-db-secret"
step "kubectl describe secret bazaar-db-secret | sed -n '/^Type/,\$p'"
step "kubectl get secret bazaar-db-secret -o jsonpath='{.data.DB_USERNAME}'; echo"
step "kubectl get secret bazaar-db-secret -o jsonpath='{.data.DB_USERNAME}' | base64 --decode; echo"
step "printf '%s' 'bazaar_owner' | base64"
step "echo 'bazaar_owner' | base64"

# --------------------------------------------- 3. apps + config injection
shot k11-04-apps-env
step "kubectl apply -f $M/frontend.yaml -f $M/backend.yaml"
step "kubectl rollout status deployment/bazaar-frontend --timeout=300s | tail -1"
step "kubectl rollout status deployment/bazaar-backend --timeout=300s | tail -1"
step "kubectl get pods,svc | grep -E 'NAME|bazaar'"
step "kubectl exec deploy/bazaar-backend -- env | grep -E 'RUNTIME_ENV|LOG_LEVEL|BASE_CURRENCY|MAX_CART_ITEMS|DB_USERNAME|DB_NAME' | sort"

# --------------------------------------------------------------- 4. Ingress
shot k11-05-ingress
step "kubectl apply -f $M/ingress.yaml"
sleep 10
step "kubectl get ingress bazaar-ingress"
step "kubectl describe ingress bazaar-ingress | sed -n '/^Rules/,/^Annotations/p'"
step "curl -s -H 'Host: bazaar.local' http://localhost:8088/ | head -12"
step "curl -s -H 'Host: bazaar.local' http://localhost:8088/api/"
step "curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H 'Host: nobody.local' http://localhost:8088/"

# ------------------------------------ 5. ConfigMap change needs a restart
shot k11-06-configmap-restart
step "kubectl patch configmap bazaar-app-config --type merge -p '{\"data\":{\"BASE_CURRENCY\":\"USD\"}}'"
step "curl -s -H 'Host: bazaar.local' http://localhost:8088/api/ | grep BASE_CURRENCY"
step "kubectl rollout restart deployment/bazaar-backend"
step "kubectl rollout status deployment/bazaar-backend --timeout=300s | tail -1"
step "kubectl get pods -l app=bazaar-backend"
# rollout status returns as soon as the NEW Pods are available, but the old ones
# are still draining and still sit in the Ingress controller's upstream list for
# a few seconds - curl too early and it is answered by an old Pod.
while kubectl get pods -l app=bazaar-backend --no-headers 2>/dev/null | grep -q Terminating; do sleep 2; done
sleep 3
step "curl -s -H 'Host: bazaar.local' http://localhost:8088/api/ | grep BASE_CURRENCY"

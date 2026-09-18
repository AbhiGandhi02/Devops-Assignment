#!/usr/bin/env bash
# Kubernetes Networking & Services - replays this section's README.
# Assumes the abhi-devops kind cluster from ../Kubernetes Fundamentals is running.
set -u
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
M=manifests
CP=abhi-devops-control-plane
WK=abhi-devops-worker

# ---------------------------------------------------------------- 1. ClusterIP
shot k10-01-clusterip
step "kubectl apply -f $M/01-clusterip/app-deployment.yaml -f $M/01-clusterip/service.yaml -f $M/01-clusterip/client-pod.yaml"
step "kubectl rollout status deployment/site-internal --timeout=300s | tail -1"
step "kubectl wait --for=condition=Ready pod/probe-client --timeout=300s"
step "kubectl get pods -l app=site-internal -o wide"
step "kubectl get svc site-internal-svc"
step "kubectl get endpointslices -l kubernetes.io/service-name=site-internal-svc"

CIP=$(kubectl get svc site-internal-svc -o jsonpath='{.spec.clusterIP}')

shot k10-02-clusterip-dns
step "kubectl exec probe-client -- curl -s http://site-internal-svc:9090 | grep -E '<title>|<h1>'"
step "kubectl exec probe-client -- curl -s -o /dev/null -w 'HTTP %{http_code} from %{remote_ip}:%{remote_port}\n' http://$CIP:9090"
step "kubectl exec probe-client -- curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://site-internal-svc.default.svc.cluster.local:9090"
step "kubectl exec probe-client -- nslookup site-internal-svc.default.svc.cluster.local"
step "kubectl exec probe-client -- cat /etc/resolv.conf"

shot k10-03-service-follows-pods
VICTIM=$(kubectl get pods -l app=site-internal -o jsonpath='{.items[0].metadata.name}')
step "kubectl get pods -l app=site-internal -o jsonpath='{range .items[*]}{.metadata.name}{\"  \"}{.status.podIP}{\"\n\"}{end}'"
step "kubectl delete pod $VICTIM"
step "kubectl rollout status deployment/site-internal --timeout=300s | tail -1"
step "kubectl get endpointslices -l kubernetes.io/service-name=site-internal-svc"
step "kubectl exec probe-client -- curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://site-internal-svc:9090"

# ----------------------------------------------------------------- 2. NodePort
shot k10-04-nodeport
step "kubectl apply -f $M/02-nodeport/app-deployment.yaml -f $M/02-nodeport/service.yaml"
step "kubectl rollout status deployment/site-nodeport --timeout=300s | tail -1"
step "kubectl get svc site-nodeport-svc"
step "kubectl get nodes -o wide | cut -c1-92"
# Give kube-proxy a moment to program the NodePort rule on every node.
# Curling a 0-second-old NodePort Service returns HTTP 000 on the node that
# holds no Pod, simply because the rule is not in place yet.
step "kubectl get endpointslices -l kubernetes.io/service-name=site-nodeport-svc"
sleep 10
step "docker exec $CP curl -s -m 5 -o /dev/null -w 'HTTP %{http_code} via worker node 172.19.0.2:30090\n' http://172.19.0.2:30090"
step "docker exec $CP curl -s -m 5 -o /dev/null -w 'HTTP %{http_code} via control-plane node 172.19.0.3:30090\n' http://172.19.0.3:30090"
step "docker exec $WK curl -s -m 5 http://localhost:30090 | grep '<title>'"

# ------------------------------------------------------------- 3. LoadBalancer
shot k10-05-loadbalancer
step "kubectl apply -f $M/03-loadbalancer/app-deployment.yaml -f $M/03-loadbalancer/service.yaml"
step "kubectl rollout status deployment/site-extlb --timeout=300s | tail -1"
step "kubectl get svc site-extlb-svc"
kubectl port-forward svc/site-extlb-svc 9080:80 >/dev/null 2>&1 &
PF=$!; sleep 4
step "curl -s -o /dev/null -w 'HTTP %{http_code} through kubectl port-forward svc/site-extlb-svc 9080:80\n' http://localhost:9080"
kill $PF 2>/dev/null; wait $PF 2>/dev/null

# ------------------------------------------------------------- 4. ExternalName
shot k10-06-externalname
step "kubectl apply -f $M/04-externalname/service.yaml -f $M/04-externalname/client-pod.yaml"
step "kubectl wait --for=condition=Ready pod/dns-probe --timeout=300s"
step "kubectl get svc remote-db-alias"
step "kubectl exec dns-probe -- nslookup remote-db-alias.default.svc.cluster.local"

# ----------------------------------------------------------------- 5. Headless
shot k10-07-headless
step "kubectl apply -f $M/05-headless/service.yaml -f $M/05-headless/app-statefulset.yaml -f $M/05-headless/client-pod.yaml"
step "kubectl rollout status statefulset/site-node --timeout=300s | tail -1"
step "kubectl wait --for=condition=Ready pod/peer-dns-probe --timeout=300s"
step "kubectl get svc site-peers"
step "kubectl get pods -l app=site-peers -o wide"
step "kubectl exec peer-dns-probe -- nslookup site-peers.default.svc.cluster.local"
step "kubectl exec peer-dns-probe -- nslookup site-node-1.site-peers.default.svc.cluster.local"
step "kubectl exec peer-dns-probe -- curl -s -o /dev/null -w 'HTTP %{http_code} from pod site-node-0\n' http://site-node-0.site-peers:80"

# ---------------------------------------------------------- 6. Troubleshooting
shot k10-08-empty-endpoints
step "kubectl apply -f $M/empty-endpoints.yaml"
step "kubectl get svc misconfigured-api-svc"
step "kubectl get endpointslices -l kubernetes.io/service-name=misconfigured-api-svc"
step "kubectl get pods --show-labels | grep -E 'NAME|site-internal' | head -4"
step "kubectl describe svc misconfigured-api-svc | grep -E 'Selector|Endpoints'"

shot k10-09-cleanup
step "kubectl delete -f $M/01-clusterip -f $M/02-nodeport -f $M/03-loadbalancer -f $M/04-externalname -f $M/05-headless -f $M/empty-endpoints.yaml"

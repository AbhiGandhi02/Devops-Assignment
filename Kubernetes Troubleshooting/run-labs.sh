#!/usr/bin/env bash
# Kubernetes Troubleshooting - replays every command in this section's README.
# Assumes the abhi-devops kind cluster (with metrics-server from the Storage/HPA section).
set -u
cd "$(dirname "$0")"
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
I=02-issues
N="-n troubleshoot"

step "kubectl create namespace troubleshoot"

# ---------------- Task 1: the commands ----------------
shot k14-01-get-wide
step "kubectl apply -f 01-commands/app.yaml"
step "kubectl rollout status deployment/orbit-shop $N --timeout=120s | tail -1"
step "kubectl get pods $N"
step "kubectl get pods $N -o wide"
step "kubectl get deploy,rs,svc,endpointslices $N"
step "kubectl get pods $N --show-labels"
step "kubectl get pods $N -o jsonpath='{range .items[*]}{.metadata.name}{\"  \"}{.status.podIP}{\"  \"}{.spec.nodeName}{\"\\n\"}{end}'"

POD=$(kubectl get pods $N -l app=orbit-shop -o jsonpath='{.items[0].metadata.name}')
shot k14-02-describe
step "kubectl describe pod $POD $N | sed -n '1,12p;/^Containers/,/^Conditions/p' | head -40"
step "kubectl describe svc orbit-shop $N"

shot k14-03-logs-exec
step "kubectl exec $N $POD -- wget -qO- localhost >/dev/null; kubectl exec $N $POD -- wget -qO- localhost/missing-page 2>/dev/null; true"
step "kubectl logs $POD $N --tail=4"
step "kubectl logs deploy/orbit-shop $N --tail=2 --timestamps"
step "kubectl exec $N $POD -- cat /etc/resolv.conf"
step "kubectl exec $N $POD -- sh -c 'hostname; nginx -v; ls /usr/share/nginx/html'"
step "kubectl exec $N $POD -- wget -qO- http://orbit-shop.troubleshoot.svc.cluster.local | grep -o '<title>.*</title>'"

shot k14-04-events-explain-top
step "kubectl events $N --types=Normal | tail -6"
step "kubectl get events $N --sort-by=.lastTimestamp | tail -4"
step "kubectl explain pod.spec.containers.livenessProbe | head -14"
step "kubectl explain deployment.spec.strategy.rollingUpdate.maxSurge"
until kubectl top pods $N >/dev/null 2>&1; do sleep 5; done
step "kubectl top nodes"
step "kubectl top pods $N"

# ---------------- Task 2: common issues ----------------
shot k14-05-crashloop-before
step "kubectl apply -f $I/01-crashloopbackoff/broken.yaml"
until kubectl get pod payments-api $N | grep -q CrashLoopBackOff; do sleep 3; done
step "kubectl get pod payments-api $N"
step "kubectl describe pod payments-api $N | grep -E 'State:|Reason:|Exit Code:|Restart Count:|Back-off'"
step "kubectl logs payments-api $N"
shot k14-06-crashloop-after
step "kubectl replace --force -f $I/01-crashloopbackoff/fixed.yaml"
kubectl wait $N --for=condition=Ready pod/payments-api --timeout=120s >/dev/null
step "kubectl get pod payments-api $N"
step "kubectl logs payments-api $N"

shot k14-07-imagepullbackoff
step "kubectl apply -f $I/02-imagepullbackoff/broken.yaml"
sleep 40
step "kubectl get pod catalog-web $N"
step "kubectl events $N --for pod/catalog-web | tail -4"
step "kubectl replace --force -f $I/02-imagepullbackoff/fixed.yaml"
kubectl wait $N --for=condition=Ready pod/catalog-web --timeout=120s >/dev/null
step "kubectl get pod catalog-web $N -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,IMAGE:.spec.containers[0].image"

shot k14-08-errimagepull
step "kubectl apply -f $I/03-errimagepull/broken.yaml"
sleep 12
step "kubectl get pod search-api $N"
step "kubectl describe pod search-api $N | grep -E 'Failed' | head -2"
step "kubectl replace --force -f $I/03-errimagepull/fixed.yaml"
kubectl wait $N --for=condition=Ready pod/search-api --timeout=120s >/dev/null
step "kubectl get pod search-api $N"
step "kubectl logs search-api $N"

shot k14-09-pending
step "kubectl apply -f $I/04-pending/broken.yaml"
sleep 8
step "kubectl get pod report-worker $N -o wide"
step "kubectl describe pod report-worker $N | sed -n '/^Events/,\$p'"
step "kubectl describe nodes | grep -A6 'Allocated resources' | grep -E 'cpu|memory'"
step "kubectl replace --force -f $I/04-pending/fixed.yaml"
kubectl wait $N --for=condition=Ready pod/report-worker --timeout=120s >/dev/null
step "kubectl get pod report-worker $N -o wide"

shot k14-10-containercreating
step "kubectl apply -f $I/05-containercreating/broken.yaml"
sleep 20
step "kubectl get pod inventory-web $N"
step "kubectl describe pod inventory-web $N | sed -n '/^Events/,\$p' | tail -3"
step "kubectl get configmap inventory-site $N"
step "kubectl apply -f $I/05-containercreating/fixed.yaml"
kubectl wait $N --for=condition=Ready pod/inventory-web --timeout=180s >/dev/null
step "kubectl get pod inventory-web $N"
step "kubectl exec inventory-web $N -- wget -qO- localhost"

shot k14-11-service-before
step "kubectl apply -f $I/06-service-connectivity/app.yaml -f $I/06-service-connectivity/broken-service.yaml -f $I/06-service-connectivity/client.yaml"
step "kubectl rollout status deployment/orders-api $N --timeout=120s | tail -1"
kubectl wait $N --for=condition=Ready pod/netshoot --timeout=180s >/dev/null
step "kubectl exec netshoot $N -- curl -s -m 3 orders-api || echo 'curl failed: exit' \$?"
step "kubectl get endpointslices $N -l kubernetes.io/service-name=orders-api"
step "kubectl get svc orders-api $N -o jsonpath='selector={.spec.selector}  targetPort={.spec.ports[0].targetPort}{\"\\n\"}'"
step "kubectl get pods $N -l app=orders-api --show-labels"
step "kubectl get pods $N -l app=orders-api -o jsonpath='{.items[0].spec.containers[0].ports[0].containerPort}{\"\\n\"}'"
shot k14-12-service-after
step "kubectl apply -f $I/06-service-connectivity/fixed-service.yaml"
sleep 4
step "kubectl get endpointslices $N -l kubernetes.io/service-name=orders-api"
step "kubectl exec netshoot $N -- curl -s -m 3 orders-api"

shot k14-13-dns-before
step "kubectl apply -f $I/07-dns/broken.yaml"
sleep 15
step "kubectl logs checkout-client $N --tail=2"
step "kubectl exec netshoot $N -- nslookup orders.default.svc.cluster.local"
step "kubectl get svc -A | grep -E 'NAMESPACE|orders'"
step "kubectl exec netshoot $N -- nslookup orders-api.troubleshoot.svc.cluster.local"
step "kubectl get pods -n kube-system -l k8s-app=kube-dns"
shot k14-14-dns-after
step "kubectl replace --force -f $I/07-dns/fixed.yaml"
kubectl wait $N --for=condition=Ready pod/checkout-client --timeout=120s >/dev/null
sleep 8
step "kubectl logs checkout-client $N --tail=2"

shot k14-15-pod-networking
step "kubectl apply -f $I/08-pod-networking/broken.yaml"
kubectl wait $N --for=condition=Ready pod/ledger-api --timeout=120s >/dev/null
IP=$(kubectl get pod ledger-api $N -o jsonpath='{.status.podIP}')
step "kubectl get pod ledger-api $N -o wide"
step "kubectl exec netshoot $N -- curl -s -m 3 http://$IP:8000 || echo 'connection failed from another Pod'"
step "kubectl exec ledger-api $N -- python3 -c \"import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000').status)\"    # works from inside"
step "kubectl exec netshoot $N -- nc -zv -w 2 $IP 8000"
step "kubectl debug ledger-api $N -q --image=nicolaka/netshoot:v0.13 --profile=general -- ss -lntp"
sleep 8
step "kubectl logs ledger-api $N -c \$(kubectl get pod ledger-api $N -o jsonpath='{.spec.ephemeralContainers[0].name}')"
step "kubectl replace --force -f $I/08-pod-networking/fixed.yaml"
kubectl wait $N --for=condition=Ready pod/ledger-api --timeout=120s >/dev/null; sleep 3
IP=$(kubectl get pod ledger-api $N -o jsonpath='{.status.podIP}')
step "kubectl exec netshoot $N -- curl -s -m 3 -o /dev/null -w 'HTTP %{http_code} from $IP\\n' http://$IP:8000"

shot k14-16-configuration
step "kubectl apply -f $I/09-configuration/broken.yaml"
sleep 10
step "kubectl get pod billing-api $N"
step "kubectl describe pod billing-api $N | grep -E 'Warning' | tail -1"
step "kubectl get configmap billing-config $N -o jsonpath='{.data}{\"\\n\"}'"
step "kubectl replace --force -f $I/09-configuration/fixed.yaml"
kubectl wait $N --for=condition=Ready pod/billing-api --timeout=120s >/dev/null
step "kubectl logs billing-api $N"

shot k14-17-oomkilled
step "kubectl apply -f $I/10-oomkilled/broken.yaml"
sleep 15
step "kubectl get pod image-resizer $N"
step "kubectl get pod image-resizer $N -o jsonpath='reason={.status.containerStatuses[0].state.terminated.reason} exitCode={.status.containerStatuses[0].state.terminated.exitCode}{\"\\n\"}'"
step "kubectl replace --force -f $I/10-oomkilled/fixed.yaml"
sleep 15
step "kubectl get pod image-resizer $N"
step "kubectl logs image-resizer $N"
step "kubectl delete namespace troubleshoot"

# ---------------- Task 3: mini project ----------------
P=03-mini-project
NP="-n ts-project"
step "kubectl create namespace ts-project"
shot k14-18-mini-deploy
step "kubectl apply -f $P/deployment.yaml -f $P/service.yaml"
step "kubectl rollout status deployment/troubleshooting-app $NP --timeout=120s | tail -1"
step "kubectl get pods,svc $NP -o wide"
MP=$(kubectl get pods $NP -l app=troubleshooting-app -o jsonpath='{.items[0].metadata.name}')
step "kubectl logs $MP $NP --tail=2"
step "kubectl exec $MP $NP -- curl -s localhost | grep -o '<title>.*</title>'"
step "kubectl describe service troubleshooting-service $NP | grep -E 'Selector|TargetPort|Endpoints'"
step "kubectl get endpointslices $NP -l kubernetes.io/service-name=troubleshooting-service"

shot k14-19-mini-broken-pod
step "kubectl apply -f $P/broken-pod.yaml"
sleep 30
step "kubectl get pod project-broken-pod $NP"
step "kubectl describe pod project-broken-pod $NP | sed -n '/^Events/,\$p'"
step "kubectl replace --force -f $P/fixed-pod.yaml"
kubectl wait $NP --for=condition=Ready pod/project-broken-pod --timeout=120s >/dev/null
step "kubectl get pod project-broken-pod $NP"

shot k14-20-mini-service
step "kubectl apply -f $P/service-broken.yaml"
step "kubectl get endpointslices $NP -l kubernetes.io/service-name=troubleshooting-service"
step "kubectl exec $MP $NP -- curl -s -m 3 troubleshooting-service || echo 'curl failed: exit' \$?"
step "kubectl get pods $NP --show-labels"
step "kubectl describe service troubleshooting-service $NP | grep Selector"
step "kubectl apply -f $P/service.yaml"
sleep 4
step "kubectl get endpointslices $NP -l kubernetes.io/service-name=troubleshooting-service"
step "kubectl exec $MP $NP -- curl -s troubleshooting-service | grep -o '<title>.*</title>'"
step "kubectl exec $MP $NP -- getent hosts troubleshooting-service.ts-project.svc.cluster.local"
step "kubectl delete namespace ts-project"

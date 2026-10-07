#!/usr/bin/env bash
# Final DevOps Project - part 5: GitOps with Argo CD (a Git change synced, drift self-healed).
set -u
cd "$(dirname "$0")"
step() { echo "\$ $1"; eval "$1" 2>&1; echo; }
shot() { echo "#==SHOT:$1==#"; }
export KUBECONFIG="$PWD/argocd.kubeconfig"     # same cluster, default namespace argocd (argocd --core)
PROD="-n readtrack-prod"
MSG=${MSG:-"Production v2 - changed in Git, synced by Argo CD"}
wait_synced() { # wait until Argo CD has applied the new value from Git
  for i in $(seq 1 60); do
    live=$(kubectl -n readtrack-prod get configmap readtrack-config -o jsonpath='{.data.WELCOME_MESSAGE}')
    if [ "$live" = "$MSG" ]; then
      echo "Argo CD applied commit $(kubectl -n argocd get application readtrack-prod -o jsonpath='{.status.sync.revision}' | cut -c1-7) after ~$((i*5))s"; return 0
    fi
    sleep 5
  done; echo "timeout, live value: $live"
}

shot k21-40-argocd-app
step "kubectl get pods -n argocd | awk '{print \$1, \$2, \$3}' | column -t"
step "kubectl get applications -n argocd"
step "argocd app get readtrack-prod --core | sed -n '1,14p'"

shot k21-41-argocd-resources
step "argocd app resources readtrack-prod --core"
step "kubectl get deploy $PROD -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image"
step "grep -E 'tag|welcome' gitops/values-gitops.yaml; git log --oneline -3 -- gitops/values-gitops.yaml"

shot k21-42-gitops-commit
step "curl -s http://readtrack.localhost:8180/api/info; echo"
step "git -C .. pull -q --rebase --autostash origin main; sed -i '' \"s|^  welcomeMessage: .*|  welcomeMessage: \\\"\$MSG\\\"|\" gitops/values-gitops.yaml && git diff -- gitops/values-gitops.yaml | tail -4"
step "git add gitops/values-gitops.yaml && git commit -q -m 'Final project GitOps demo: change the prod welcome message in Git' -- gitops/values-gitops.yaml && for i in 1 2 3; do git -C .. pull -q --rebase --autostash origin main && git -C .. push -q origin main && break; sleep 5; done; git log --oneline -1"

shot k21-43-gitops-synced
step "kubectl -n argocd annotate application readtrack-prod argocd.argoproj.io/refresh=normal --overwrite >/dev/null; wait_synced"
step "kubectl $PROD rollout status deploy/readtrack-backend --timeout=180s | tail -1"
step "curl -s http://readtrack.localhost:8180/api/info; echo"
step "argocd app history readtrack-prod --core | tail -4"

shot k21-44-self-heal
step "kubectl $PROD delete service readtrack-backend; kubectl $PROD patch configmap readtrack-config -p '{\"data\":{\"LOG_LEVEL\":\"DEBUG\"}}'; kubectl $PROD delete ingress readtrack"
step "sleep 3; kubectl get application readtrack-prod -n argocd -o jsonpath='{.status.sync.status}{\"\\n\"}'"
step "sleep 25; kubectl get application readtrack-prod -n argocd -o jsonpath='{.status.sync.status} {.status.health.status}{\"\\n\"}'"
step "kubectl $PROD get svc readtrack-backend -o name; kubectl $PROD get configmap readtrack-config -o jsonpath='LOG_LEVEL={.data.LOG_LEVEL}{\"\\n\"}'; kubectl $PROD get ingress readtrack; curl -s -o /dev/null -w 'app via ingress -> %{http_code}\\n' http://readtrack.localhost:8180/"
step "kubectl -n argocd logs argocd-application-controller-0 --since=60s | grep -oE 'Initiated automated sync to [^\"]*|self-heal[^\"]*' | sort -u | head -4"

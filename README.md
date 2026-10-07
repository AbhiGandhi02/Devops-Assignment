# DevOps Assignment

**Name:** Abhi Gandhi
**Enrollment Number:** 24bcs10397

My DevOps course assignment. Every topic has its own folder containing the commands I ran,
the output from my terminal, screenshots, and what I understood from each task.

## Submission index

| Session | Topic | Write-up |
|---|---|---|
| 1 & 2 | Linux Fundamentals | [Linux Fundamentals/README.md](Linux%20Fundamentals/README.md) |
| 3 | Shell Scripting | [Shell Scripting/README.md](Shell%20Scripting/README.md) |
| 4 | Networking Fundamentals | [Networking Fundamentals/networking.md](Networking%20Fundamentals/networking.md) |
| 5 | Git and GitHub | [Git and Github/git-tasks.md](Git%20and%20Github/git-tasks.md) |
| 6 | Docker Fundamentals | [Docker Fundamentals/README.md](Docker%20Fundamentals/README.md) |
| 7 | Dockerfiles and Images | [DockerFiles and Images/README.md](DockerFiles%20and%20Images/README.md) |
| 8 | Docker Networking and Volumes | [Docker Networks/README.md](Docker%20Networks/README.md) |
| 9 | Kubernetes Fundamentals | [Kubernetes Fundamentals/README.md](Kubernetes%20Fundamentals/README.md) |
| 10 | Kubernetes Pods, ReplicaSets and Deployments | [Kubernetes Pods ReplicaSets and Deployments/README.md](Kubernetes%20Pods%20ReplicaSets%20and%20Deployments/README.md) |
| 11 | Kubernetes Networking and Services | [Kubernetes Networking and Services/README.md](Kubernetes%20Networking%20and%20Services/README.md) |
| 12 | Kubernetes Ingress, ConfigMaps and Secrets | [Kubernetes Ingress ConfigMaps and Secrets/README.md](Kubernetes%20Ingress%20ConfigMaps%20and%20Secrets/README.md) |
| 13 | Kubernetes Storage, HPA and Probes | [Kubernetes Storage HPA and Probes/README.md](Kubernetes%20Storage%20HPA%20and%20Probes/README.md) |
| 14 | Kubernetes Troubleshooting | [Kubernetes Troubleshooting/README.md](Kubernetes%20Troubleshooting/README.md) |
| 15 | Helm | [Helm/README.md](Helm/README.md) |
| 16 | CI/CD and GitHub Actions | [CI-CD and GitHub Actions/README.md](CI-CD%20and%20GitHub%20Actions/README.md) |
| 17 | Complete CI/CD and DevSecOps | [DevSecOps/README.md](DevSecOps/README.md) |
| 18 | Terraform and Infrastructure as Code | [Terraform and Infrastructure as Code/README.md](Terraform%20and%20Infrastructure%20as%20Code/README.md) |
| 19 | Cloud and Terraform in Action | [Cloud and Terraform in Action/README.md](Cloud%20and%20Terraform%20in%20Action/README.md) |
| 20 | Monitoring, Observability and GitOps | [Monitoring Observability and GitOps/README.md](Monitoring%20Observability%20and%20GitOps/README.md) |
| 21 | Final DevOps Project and Troubleshooting | [Final DevOps Project/README.md](Final%20DevOps%20Project/README.md) |

## GitHub Actions pipelines

GitHub only runs workflows from the repository root, so all pipelines live in
[.github/workflows/](.github/workflows). Each one has a `paths:` filter and runs only when its
own folder changes.

| Workflow | Session | What it does |
|---|---|---|
| [s16-ci.yml](.github/workflows/s16-ci.yml) | 16 | lint, test matrix (Python 3.11-3.13), build artifact, Docker image push to GHCR |
| [s16-cd.yml](.github/workflows/s16-cd.yml) | 16 | runs after CI succeeds; deploys that exact image to Kubernetes (kind) and smoke-tests it |
| [s17-devsecops.yml](.github/workflows/s17-devsecops.yml) | 17 | build, test, SAST, SCA, secret scan, image scan, security gate, push, deploy |
| [final-project.yml](.github/workflows/final-project.yml) | 21 | full CI/CD + DevSecOps for ReadTrack, then the GitOps image-tag bump that Argo CD syncs |

## Environment

- macOS (Apple Silicon) with Docker Desktop
- Linux tasks: `ubuntu` container
- Kubernetes: a local 2-node cluster created with [kind](https://kind.sigs.k8s.io/),
  named `abhi-devops` - config in
  [Kubernetes Fundamentals/kind-cluster.yaml](Kubernetes%20Fundamentals/kind-cluster.yaml).
  The final project uses its own kind cluster, `abhi-final`.
- Tools: kubectl, kind, Helm 4, Terraform 1.16, Trivy, Bandit, Semgrep, pip-audit, Gitleaks,
  Prometheus/Grafana/Loki, Jaeger, Argo CD
- AWS (Sessions 18, 19, 21): Terraform ran against [LocalStack](https://www.localstack.cloud/)
  4.12, a local emulator of the AWS APIs, because my AWS credentials were not usable. Each
  README explains how to point the same code at real AWS.

## Reproducing the sections

Every hands-on section has a `run-labs.sh` that replays every command in its README. Each
script echoes every command before running it, so its output is a transcript that matches the
README. The screenshots in each `screenshots/` folder were captured from these runs.

The Kubernetes sections (9-15 and 20) share one cluster. Create it once:

```bash
cd "Kubernetes Fundamentals"
kind create cluster --config kind-cluster.yaml
./run-labs.sh

cd "../Kubernetes Pods ReplicaSets and Deployments" && ./run-labs.sh
cd "../Kubernetes Networking and Services"          && ./run-labs.sh
cd "../Kubernetes Ingress ConfigMaps and Secrets"   && ./run-labs.sh
cd "../Kubernetes Storage HPA and Probes"           && ./run-labs.sh   # installs metrics-server
cd "../Kubernetes Troubleshooting"                  && ./run-labs.sh
cd "../Helm"                                        && ./run-labs.sh
cd "../Monitoring Observability and GitOps"         && ./run-labs.sh

# when finished
kind delete cluster --name abhi-devops
```

The Terraform sections need LocalStack running first:

```bash
docker run -d --name localstack -p 4566:4566 localstack/localstack:4.12
"Terraform and Infrastructure as Code/run-labs.sh"
"Cloud and Terraform in Action/run-labs.sh"
```

The final project has its own setup steps in
[Final DevOps Project/README.md](Final%20DevOps%20Project/README.md).

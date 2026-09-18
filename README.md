# DevOps Assignment 1

**Name:** Abhi Gandhi
**Enrollment Number:** 24bcs10397

My DevOps course assignment. Every topic has its own folder containing the commands I ran,
the output from my terminal, screenshots, and what I understood from each task.

## Submission index

| # | Topic | Write-up |
|---|---|---|
| 1 | Linux Fundamentals | [Linux Fundamentals/README.md](Linux%20Fundamentals/README.md) |
| 2 | Shell Scripting | [Shell Scripting/README.md](Shell%20Scripting/README.md) |
| 3 | Networking Fundamentals | [Networking Fundamentals/networking.md](Networking%20Fundamentals/networking.md) |
| 4 | Git and GitHub | [Git and Github/git-tasks.md](Git%20and%20Github/git-tasks.md) |
| 5 | Docker Fundamentals | [Docker Fundamentals/README.md](Docker%20Fundamentals/README.md) |
| 6 | Dockerfiles and Images | [DockerFiles and Images/README.md](DockerFiles%20and%20Images/README.md) |
| 7 | Docker Networking and Volumes | [Docker Networks/README.md](Docker%20Networks/README.md) |
| 8 | Kubernetes Fundamentals | [Kubernetes Fundamentals/README.md](Kubernetes%20Fundamentals/README.md) |
| 9 | Kubernetes Pods, ReplicaSets and Deployments | [Kubernetes Pods ReplicaSets and Deployments/README.md](Kubernetes%20Pods%20ReplicaSets%20and%20Deployments/README.md) |
| 10 | Kubernetes Networking and Services | [Kubernetes Networking and Services/README.md](Kubernetes%20Networking%20and%20Services/README.md) |
| 11 | Kubernetes Ingress, ConfigMaps and Secrets | [Kubernetes Ingress ConfigMaps and Secrets/README.md](Kubernetes%20Ingress%20ConfigMaps%20and%20Secrets/README.md) |

## Environment

- macOS (Apple Silicon) with Docker Desktop
- Linux tasks: `ubuntu` container
- Kubernetes: a local 2-node cluster created with [kind](https://kind.sigs.k8s.io/),
  named `abhi-devops` - config in
  [Kubernetes Fundamentals/kind-cluster.yaml](Kubernetes%20Fundamentals/kind-cluster.yaml)

## Reproducing the Kubernetes sections

The four Kubernetes topics share one cluster. Create it once, then each section has a
`run-labs.sh` that replays every command in that section's README:

```bash
cd "Kubernetes Fundamentals"
kind create cluster --config kind-cluster.yaml
./run-labs.sh

cd "../Kubernetes Pods ReplicaSets and Deployments" && ./run-labs.sh
cd "../Kubernetes Networking and Services"          && ./run-labs.sh
cd "../Kubernetes Ingress ConfigMaps and Secrets"   && ./run-labs.sh

# when finished
kind delete cluster --name abhi-devops
```

Each script echoes every command before running it, so its output is a transcript that
matches the README. The screenshots in each `screenshots/` folder were captured from these
runs.

# The local Kubernetes cluster, also as code. kind runs Kubernetes nodes as Docker containers;
# the control-plane is labelled ingress-ready and maps host ports 8180/8543 to 80/443 for ingress-nginx.
terraform {
  required_version = ">= 1.6"
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.9"
    }
  }
}

variable "cluster_name" {
  type    = string
  default = "abhi-final"
}

variable "node_image" {
  type    = string
  default = "kindest/node:v1.34.0@sha256:7416a61b42b1662ca6ca89f02028ac133a309a2a30ba309614e8ec94d976dc5a"
}

resource "kind_cluster" "this" {
  name            = var.cluster_name
  node_image      = var.node_image
  wait_for_ready  = true
  kubeconfig_path = abspath("${path.module}/../../.kubeconfig")

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]
      extra_port_mappings {
        container_port = 80
        host_port      = 8180
        listen_address = "127.0.0.1"
      }
      extra_port_mappings {
        container_port = 443
        host_port      = 8543
        listen_address = "127.0.0.1"
      }
    }

    node {
      role = "worker"
    }
  }
}

output "endpoint" {
  value = kind_cluster.this.endpoint
}

output "kubeconfig_path" {
  value = kind_cluster.this.kubeconfig_path
}

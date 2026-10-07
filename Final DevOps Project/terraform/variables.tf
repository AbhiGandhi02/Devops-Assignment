variable "project" {
  description = "Name prefix for every resource"
  type        = string
  default     = "readtrack"
}

variable "owner" {
  type    = string
  default = "abhi-gandhi-24bcs10397"
}

variable "environment" {
  type    = string
  default = "dev"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "use_localstack" {
  description = "Send all API calls to LocalStack instead of real AWS"
  type        = bool
  default     = true
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "One public subnet per AZ (load balancers / ingress)"
  type        = list(string)
  default     = ["10.42.0.0/24", "10.42.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "One private subnet per AZ (EKS worker nodes)"
  type        = list(string)
  default     = ["10.42.10.0/24", "10.42.11.0/24"]
}

variable "enable_eks" {
  description = "Create the EKS control plane + node group. EKS is a LocalStack Pro feature, so this stays false on LocalStack community and is true on real AWS."
  type        = bool
  default     = false
}

variable "kubernetes_version" {
  type    = string
  default = "1.33"
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "node_count" {
  type = object({ min = number, desired = number, max = number })
  default = {
    min     = 1
    desired = 2
    max     = 3
  }
}

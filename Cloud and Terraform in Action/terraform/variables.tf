variable "project" {
  description = "Name prefix for every resource"
  type        = string
  default     = "orbit-web"
}

variable "owner" {
  description = "Person responsible for the resources"
  type        = string
}

variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "vpc_cidr" {
  description = "Address range of the whole VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Subnet with a route to the Internet Gateway (web server)"
  type        = string
  default     = "10.20.1.0/24"
}

variable "private_subnet_cidr" {
  description = "Subnet with no internet route (for a future database)"
  type        = string
  default     = "10.20.2.0/24"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"

  validation {
    condition     = contains(["t3.micro", "t3.small", "t2.micro", "m5.large"], var.instance_type)
    error_message = "Allowed: t3.micro, t3.small, t2.micro (Free Tier) or m5.large (LocalStack only - see README)."
  }
}

variable "ami_owners" {
  description = "Who publishes the AMI (099720109477 = Canonical)"
  type        = list(string)
  default     = ["099720109477"]
}

variable "ami_name_pattern" {
  description = "Name filter for the most recent matching AMI"
  type        = string
  default     = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
}

variable "ssh_cidr" {
  description = "Only this range may SSH to the instance (your own IP/32)"
  type        = string
  default     = "203.0.113.10/32"
}

variable "use_localstack" {
  type    = bool
  default = false
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

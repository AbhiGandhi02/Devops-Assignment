data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name         = "${var.project}-${var.environment}"
  azs          = slice(data.aws_availability_zones.available.names, 0, 2)
  cluster_name = "${local.name}-eks"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # EKS nodes need DNS hostnames
  tags                 = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-igw" }
}

# Two public subnets in two AZs. The kubernetes.io/role/elb tag tells the AWS load balancer
# controller where internet-facing load balancers (the Ingress) may be placed.
# map_public_ip_on_launch stays false: nothing here needs an automatic public IP (the load
# balancer and NAT gateway get their own), so no instance becomes public by accident.
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false
  tags = {
    Name                                          = "${local.name}-public-${local.azs[count.index]}"
    Tier                                          = "public"
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags = {
    Name                                          = "${local.name}-private-${local.azs[count.index]}"
    Tier                                          = "private"
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${local.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private subnets egress through one NAT gateway (one is enough for a student project;
# production would use one per AZ).
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${local.name}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${local.name}-nat" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${local.name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security group for the worker nodes: nodes talk to each other freely, ingress
# traffic only reaches the NodePort range from inside the VPC (the load balancer).
resource "aws_security_group" "nodes" {
  name        = "${local.name}-nodes"
  description = "EKS worker nodes"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-nodes-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "nodes_self" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
  description                  = "node to node"
}

resource "aws_vpc_security_group_ingress_rule" "nodeports_from_vpc" {
  security_group_id = aws_security_group.nodes.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 30000
  to_port           = 32767
  description       = "NodePorts from the load balancer inside the VPC"
}

# Accepted risk (Trivy AWS-0104): worker nodes must reach GHCR/ECR and the EKS API on the
# internet; the traffic leaves through the NAT gateway and nothing can connect back in.
#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "nodes_all" {
  security_group_id = aws_security_group.nodes.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "all egress (image pulls, AWS APIs)"
}

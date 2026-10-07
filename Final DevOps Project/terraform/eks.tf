# EKS control plane + managed node group.
# count = 0 on LocalStack community (EKS is a Pro feature) - `terraform plan -var enable_eks=true`
# still shows exactly what would be created on real AWS. Locally the same Helm chart runs on kind.

resource "aws_eks_cluster" "main" {
  count    = var.enable_eks ? 1 : 0
  name     = local.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  access_config {
    authentication_mode = "API"
  }

  enabled_cluster_log_types = ["api", "audit"]
  depends_on                = [aws_iam_role_policy_attachment.cluster]
}

resource "aws_eks_node_group" "default" {
  count           = var.enable_eks ? 1 : 0
  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "${local.name}-ng"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = [var.node_instance_type]

  scaling_config {
    min_size     = var.node_count.min
    desired_size = var.node_count.desired
    max_size     = var.node_count.max
  }

  update_config {
    max_unavailable = 1
  }

  labels     = { workload = "readtrack" }
  depends_on = [aws_iam_role_policy_attachment.nodes]
}

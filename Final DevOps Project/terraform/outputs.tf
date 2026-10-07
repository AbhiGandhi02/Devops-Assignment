output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "availability_zones" {
  value = local.azs
}

output "node_security_group_id" {
  value = aws_security_group.nodes.id
}

output "eks_cluster_role_arn" {
  value = aws_iam_role.cluster.arn
}

output "eks_node_role_arn" {
  value = aws_iam_role.nodes.arn
}

output "eks_cluster_name" {
  value = var.enable_eks ? aws_eks_cluster.main[0].name : "(disabled - EKS needs real AWS or LocalStack Pro; kind is used locally)"
}

output "artifacts_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}

output "kubeconfig_command" {
  value = var.enable_eks ? "aws eks update-kubeconfig --region ${var.aws_region} --name ${local.cluster_name}" : "kind get kubeconfig --name abhi-final"
}

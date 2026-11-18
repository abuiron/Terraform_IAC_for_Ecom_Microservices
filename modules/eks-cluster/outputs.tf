output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA certificate of the Kubernetes API."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group EKS created for the cluster; Auto Mode nodes use it too."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "kubernetes_version" {
  description = "Kubernetes version the control plane runs."
  value       = aws_eks_cluster.this.version
}

output "node_role_name" {
  description = "IAM role of the Auto Mode nodes."
  value       = aws_iam_role.node.name
}

output "ingress_class" {
  description = "IngressClass the API ingress uses."
  value       = kubernetes_ingress_class_v1.alb.metadata[0].name
}

output "uploads_storage_class" {
  description = "StorageClass for the shared uploads volume."
  value       = kubernetes_storage_class_v1.efs_uploads.metadata[0].name
}

output "app_node_pool" {
  description = "NodePool the app pods prefer."
  value       = "looksmatter-apps"
}

output "external_secrets_role_arn" {
  description = "IAM role the External Secrets Operator uses."
  value       = aws_iam_role.external_secrets.arn
}

output "service_name" {
  description = "Kubernetes Service name."
  value       = kubernetes_service_v1.this.metadata[0].name
}

output "service_port" {
  description = "Port the Service exposes."
  value       = var.port
}

output "deployment_name" {
  description = "Deployment name (for kubectl rollout commands)."
  value       = kubernetes_deployment_v1.this.metadata[0].name
}

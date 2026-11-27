output "api_url" {
  description = "Public API base URL; build the storefront with VITE_API_BASE_URL set to this."
  value       = "https://${local.infra.api_domain}/api"
}

output "load_balancer_hostname" {
  description = "The ALB's own hostname (api domain points here)."
  value       = kubernetes_ingress_v1.api.status[0].load_balancer[0].ingress[0].hostname
}

output "deployed_images" {
  description = "Exact image (tag and digest) running per service."
  value       = local.images
}

output "namespace" {
  description = "Kubernetes namespace of the application."
  value       = kubernetes_namespace_v1.app.metadata[0].name
}

output "useful_commands" {
  description = "Handy kubectl commands for this environment."
  value = {
    pods        = "kubectl -n ${local.namespace} get pods -o wide"
    autoscalers = "kubectl -n ${local.namespace} get hpa"
    logs        = "kubectl -n ${local.namespace} logs deploy/order-service -f"
    restart     = "kubectl -n ${local.namespace} rollout restart deploy/core-service deploy/order-service"
    nodes       = "kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type,topology.kubernetes.io/zone"
  }
}

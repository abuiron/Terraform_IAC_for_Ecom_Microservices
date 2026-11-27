variable "project" {
  description = "Short project name."
  type        = string
  default     = "looksmatter"
}

variable "environment" {
  description = "Environment name; must match the infrastructure stack."
  type        = string
}

variable "region" {
  description = "AWS region; must match the infrastructure stack."
  type        = string
  default     = "ap-south-1"
}

variable "namespace" {
  description = "Kubernetes namespace for the application."
  type        = string
  default     = "looksmatter"
}

# ---------------------------------------------------------------------------------------
# Release
# ---------------------------------------------------------------------------------------

variable "image_tag" {
  description = "Image tag to deploy for all three services, normally the backend's git commit (scripts/build-and-push.sh prints it). Pass it on the command line: -var image_tag=<tag>."
  type        = string

  validation {
    condition     = length(var.image_tag) > 0 && var.image_tag != "latest"
    error_message = "Set image_tag to an immutable tag such as a git commit; \"latest\" is not allowed."
  }
}

variable "image_tag_overrides" {
  description = "Deploy a different tag for one service, e.g. { \"order-service\" = \"abc123\" }."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------------------
# Sizing and autoscaling
# ---------------------------------------------------------------------------------------

variable "services" {
  description = <<-EOT
    Per-service sizing and autoscaling.
      min/max_replicas  HorizontalPodAutoscaler range (min 2 = survives losing a node or zone)
      target_cpu        average CPU, in percent of cpu_request, the autoscaler aims for
      cpu_request       CPU reserved per pod; also the 100% mark for target_cpu
      memory_request    memory reserved per pod
      memory_limit      the pod restarts above this; must be in Mi (Node's heap is set to 75% of it)
  EOT
  type = map(object({
    min_replicas   = number
    max_replicas   = number
    target_cpu     = number
    cpu_request    = string
    memory_request = string
    memory_limit   = string
  }))
  default = {
    "gateway"       = { min_replicas = 2, max_replicas = 6, target_cpu = 70, cpu_request = "100m", memory_request = "128Mi", memory_limit = "256Mi" }
    "core-service"  = { min_replicas = 2, max_replicas = 10, target_cpu = 70, cpu_request = "250m", memory_request = "256Mi", memory_limit = "512Mi" }
    "order-service" = { min_replicas = 2, max_replicas = 10, target_cpu = 70, cpu_request = "250m", memory_request = "256Mi", memory_limit = "512Mi" }
  }

  validation {
    condition     = toset(keys(var.services)) == toset(["gateway", "core-service", "order-service"])
    error_message = "services must have exactly the keys gateway, core-service and order-service."
  }

  validation {
    condition     = alltrue([for service in values(var.services) : can(regex("^[0-9]+Mi$", service.memory_limit))])
    error_message = "memory_limit must be written in Mi, e.g. 512Mi."
  }
}

# ---------------------------------------------------------------------------------------
# Application settings
# ---------------------------------------------------------------------------------------

variable "extra_cors_origins" {
  description = "Browser origins allowed to call the API besides the storefront domains, e.g. [\"http://localhost:5173\"] in staging."
  type        = list(string)
  default     = []
}

variable "proxy_timeout_ms" {
  description = "How long the gateway waits for a service before answering 504."
  type        = number
  default     = 30000
}

variable "payment_webhook_path" {
  description = "Path the payment provider calls after a payment (sent to the provider as the callback URL)."
  type        = string
  default     = "/api/payment/webhook"
}

variable "uploads_volume_size" {
  description = "Requested size of the uploads volume. EFS grows automatically; Kubernetes just needs a number."
  type        = string
  default     = "10Gi"
}

variable "enable_network_policies" {
  description = "Allow only the expected pod-to-pod traffic (requires enable_network_policy in the platform stack)."
  type        = bool
  default     = true
}

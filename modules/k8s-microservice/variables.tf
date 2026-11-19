variable "name" {
  description = "Service name; also the Kubernetes Service DNS name (e.g. core-service)."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace."
  type        = string
}

variable "part_of" {
  description = "Application the service belongs to (app.kubernetes.io/part-of label)."
  type        = string
  default     = "looksmatter"
}

variable "image" {
  description = "Container image, ideally pinned by digest: <repo>:<tag>@sha256:<digest>."
  type        = string
}

variable "port" {
  description = "Port the app listens on (the Service exposes the same port)."
  type        = number
}

variable "env" {
  description = "Plain (non-secret) environment variables."
  type        = map(string)
  default     = {}
}

variable "secret_name" {
  description = "Kubernetes Secret whose keys become environment variables (created by the External Secrets Operator). null = none."
  type        = string
  default     = null
}

variable "readiness_path" {
  description = "HTTP path that answers 200 when the pod can take traffic."
  type        = string
  default     = "/health"
}

variable "resources" {
  description = "CPU/memory requests (what the scheduler reserves) and the memory limit (the pod is restarted above it). No CPU limit on purpose: it throttles Node.js under load."
  type = object({
    cpu_request    = string
    memory_request = string
    memory_limit   = string
  })
}

variable "autoscaling" {
  description = "HorizontalPodAutoscaler settings: replica range and the average CPU (percent of the request) to aim for."
  type = object({
    min_replicas           = number
    max_replicas           = number
    target_cpu_utilization = number
  })

  validation {
    condition     = var.autoscaling.min_replicas >= 1 && var.autoscaling.max_replicas >= var.autoscaling.min_replicas
    error_message = "Need min_replicas >= 1 and max_replicas >= min_replicas."
  }
}

variable "volume" {
  description = "Optional persistent volume claim to mount, e.g. the shared uploads folder."
  type = object({
    claim_name = string
    mount_path = string
  })
  default = null
}

variable "min_ready_seconds" {
  description = "How long a new pod must stay ready before the rollout counts it and stops an old one. Behind a load balancer, give it time to pass the load balancer's own health checks."
  type        = number
  default     = 10
}

variable "termination_grace_period_seconds" {
  description = "Time a pod gets to finish in-flight requests after it is told to stop."
  type        = number
  default     = 30
}

variable "pre_stop_sleep_seconds" {
  description = "Delay before the app gets SIGTERM, so the load balancer and Services stop sending it new requests first."
  type        = number
  default     = 10
}

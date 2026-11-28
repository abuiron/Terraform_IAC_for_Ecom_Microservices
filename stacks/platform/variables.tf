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

# ---------------------------------------------------------------------------------------
# Node autoscaling (the "looksmatter-apps" NodePool)
# ---------------------------------------------------------------------------------------

variable "node_capacity_types" {
  description = "spot and/or on-demand. Spot can be up to 90% cheaper but AWS may reclaim it with 2 minutes' notice; the services tolerate that (several replicas, disruption budgets)."
  type        = list(string)
  default     = ["on-demand"]

  validation {
    condition     = length(var.node_capacity_types) > 0 && alltrue([for type in var.node_capacity_types : contains(["spot", "on-demand"], type)])
    error_message = "node_capacity_types may contain only spot and on-demand."
  }
}

variable "node_architectures" {
  description = "CPU architectures for app nodes. Add arm64 (cheaper Graviton) only once images are built for both (docker buildx --platform linux/amd64,linux/arm64)."
  type        = list(string)
  default     = ["amd64"]
}

variable "node_instance_categories" {
  description = "EC2 families: c = compute, m = general purpose, r = memory. More choice = better spot availability."
  type        = list(string)
  default     = ["c", "m", "r"]
}

variable "node_min_generation" {
  description = "Only instance generations newer than this (e.g. 4 → 5th generation and newer)."
  type        = number
  default     = 4
}

variable "node_pool_cpu_limit" {
  description = "Maximum total vCPUs this node pool may run: a hard ceiling on autoscaling cost."
  type        = number
  default     = 32
}

variable "node_pool_memory_limit_gib" {
  description = "Maximum total memory (GiB) this node pool may run."
  type        = number
  default     = 128
}

variable "node_consolidate_after" {
  description = "How long a node must be empty or underused before it is removed or replaced by a cheaper one."
  type        = string
  default     = "5m"
}

# ---------------------------------------------------------------------------------------
# Add-ons
# ---------------------------------------------------------------------------------------

variable "enable_network_policy" {
  description = "Turn on Kubernetes NetworkPolicy enforcement in EKS Auto Mode (the workloads stack defines the policies)."
  type        = bool
  default     = true
}

variable "alb_ssl_policy" {
  description = "TLS policy of the API load balancer's HTTPS listener (TLS 1.3 + 1.2)."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "metrics_server_chart_version" {
  description = "metrics-server Helm chart version (https://github.com/kubernetes-sigs/metrics-server/releases, tags metrics-server-helm-chart-*)."
  type        = string
  default     = "3.14.0"
}

variable "external_secrets_chart_version" {
  description = "External Secrets Operator Helm chart version (https://github.com/external-secrets/external-secrets/releases, tags helm-chart-*)."
  type        = string
  default     = "2.15.0"
}

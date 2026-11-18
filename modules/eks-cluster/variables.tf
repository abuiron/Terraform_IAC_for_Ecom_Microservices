variable "name" {
  description = "Cluster name, e.g. looksmatter-production."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version, e.g. 1.37. Check https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the control plane network interfaces and the nodes (at least 2 zones)."
  type        = list(string)
}

variable "endpoint_public_access_cidrs" {
  description = "Who may reach the Kubernetes API from the internet (still requires IAM auth). Narrow this to your office/VPN and CI IPs."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_principal_arns" {
  description = "Extra IAM users/roles that get cluster-admin. Don't list the identity that runs Terraform: it is made admin automatically."
  type        = list(string)
  default     = []
}

variable "built_in_node_pools" {
  description = "EKS Auto Mode's built-in node pools. Keep both: add-ons schedule onto them, and they create the 'default' NodeClass that custom node pools reuse."
  type        = list(string)
  default     = ["general-purpose", "system"]

  validation {
    condition     = length(var.built_in_node_pools) > 0 && alltrue([for pool in var.built_in_node_pools : contains(["general-purpose", "system"], pool)])
    error_message = "built_in_node_pools must contain at least one of: general-purpose, system."
  }
}

variable "enabled_log_types" {
  description = "Control plane logs sent to CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "log_retention_days" {
  description = "How long CloudWatch keeps control plane logs."
  type        = number
  default     = 30
}

variable "deletion_protection" {
  description = "Block cluster deletion until this is turned off. Use true in production."
  type        = bool
  default     = false
}

variable "enable_container_insights" {
  description = "Install the Amazon CloudWatch Observability add-on: container logs and metrics in CloudWatch."
  type        = bool
  default     = true
}

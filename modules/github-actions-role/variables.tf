variable "name" {
  description = "IAM role name."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the account's GitHub Actions OIDC provider (created by the shared stack)."
  type        = string
}

variable "repository" {
  description = "GitHub repository allowed to assume the role, as owner/name, e.g. abuiron/looksmatter_bc."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.repository))
    error_message = "repository must look like owner/name."
  }
}

variable "branches" {
  description = "Branches whose workflows may assume the role."
  type        = list(string)
  default     = ["main"]
}

variable "environments" {
  description = "GitHub environments whose jobs may assume the role. A job with `environment:` presents an environment claim instead of a branch claim."
  type        = list(string)
  default     = []
}

variable "policy_json" {
  description = "IAM policy (JSON) with exactly the permissions the workflow needs."
  type        = string
}

variable "max_session_duration" {
  description = "Maximum session length in seconds."
  type        = number
  default     = 3600
}

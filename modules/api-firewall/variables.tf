variable "name" {
  description = "Web ACL name, e.g. looksmatter-production-api."
  type        = string
}

variable "rate_limit_per_5_minutes" {
  description = "Requests one IP may send in any 5-minute window before it is blocked. Kept high on purpose: Indian mobile carriers put many shoppers behind one IP (CGNAT)."
  type        = number
  default     = 10000

  validation {
    condition     = var.rate_limit_per_5_minutes >= 10
    error_message = "AWS WAF rate limits must be at least 10."
  }
}

variable "auth_rate_limit_per_5_minutes" {
  description = "Stricter limit for /api/auth/* (login, register) per IP in 5 minutes: slows down password guessing."
  type        = number
  default     = 300

  validation {
    condition     = var.auth_rate_limit_per_5_minutes >= 10
    error_message = "AWS WAF rate limits must be at least 10."
  }
}

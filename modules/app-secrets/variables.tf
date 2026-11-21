variable "prefix" {
  description = "Secret name prefix, e.g. looksmatter/production. Secrets are named <prefix>/<name>."
  type        = string
}

variable "recovery_window_in_days" {
  description = "Days a deleted secret can still be restored (7–30, or 0 to delete immediately)."
  type        = number
  default     = 30

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "recovery_window_in_days must be 0 or between 7 and 30."
  }
}

variable "shared_secrets_version" {
  description = "Increase by one to generate and store a new JWT_SECRET and INTERNAL_API_KEY (rotation). Rotating JWT_SECRET signs every shopper out."
  type        = number
  default     = 1
}

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

variable "atlas_org_id" {
  description = "MongoDB Atlas organization id (Atlas UI → Organization → Settings)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{24}$", var.atlas_org_id))
    error_message = "atlas_org_id must be the 24-character hex id from Atlas → Organization → Settings."
  }
}

variable "instance_size" {
  description = "Starting/minimum Atlas tier."
  type        = string
  default     = "M10"
}

variable "max_instance_size" {
  description = "Largest tier auto-scaling may reach."
  type        = string
  default     = "M30"
}

variable "mongo_db_major_version" {
  description = "MongoDB major version."
  type        = string
  default     = "8.0"
}

variable "backup_enabled" {
  description = "Cloud backups."
  type        = bool
  default     = true
}

variable "pit_enabled" {
  description = "Point-in-time restore."
  type        = bool
  default     = true
}

variable "termination_protection_enabled" {
  description = "Block cluster deletion until turned off."
  type        = bool
  default     = true
}

variable "admin_access_cidrs" {
  description = "Extra IPs allowed to connect, e.g. your office for running migrations: { \"office\" = \"203.0.113.10/32\" }. Remove them when done."
  type        = map(string)
  default     = {}
}

variable "credentials_version" {
  description = "Bump to rotate both services' database passwords (then restart core-service and order-service)."
  type        = number
  default     = 1
}

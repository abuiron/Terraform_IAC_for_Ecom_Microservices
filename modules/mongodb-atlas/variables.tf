variable "org_id" {
  description = "MongoDB Atlas organization id (Atlas UI → Organization → Settings)."
  type        = string
}

variable "project_name" {
  description = "Atlas project to create, e.g. looksmatter-production."
  type        = string
}

variable "cluster_name" {
  description = "Atlas cluster name, e.g. looksmatter-production."
  type        = string
}

variable "aws_region" {
  description = "AWS region of the cluster, e.g. ap-south-1. Keep it next to EKS for low latency."
  type        = string
}

variable "instance_size" {
  description = "Starting (and minimum) cluster tier. M10 is the smallest dedicated tier with backups and auto-scaling."
  type        = string
  default     = "M10"
}

variable "max_instance_size" {
  description = "Largest tier compute auto-scaling may grow to."
  type        = string
  default     = "M30"
}

variable "mongo_db_major_version" {
  description = "MongoDB major version."
  type        = string
  default     = "8.0"
}

variable "backup_enabled" {
  description = "Cloud backups (snapshots)."
  type        = bool
  default     = true
}

variable "pit_enabled" {
  description = "Point-in-time restore (restore to any second in the retention window). Needs backup_enabled."
  type        = bool
  default     = true
}

variable "termination_protection_enabled" {
  description = "Atlas refuses to delete the cluster until this is turned off. Use true in production."
  type        = bool
  default     = true
}

variable "allowed_cidrs" {
  description = "Who may connect, as { comment = cidr }. Always include the NAT gateway IPs of the VPC."
  type        = map(string)
}

variable "database_users" {
  description = "One database user per service, allowed to read and write only its own database, and the Secrets Manager secret that receives its MONGO_URI."
  type = map(object({
    database  = string
    secret_id = string
  }))
}

variable "credentials_version" {
  description = "Increase by one to generate new database passwords and write new MONGO_URI secrets (rotation). Restart the pods afterwards."
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags for the Atlas project and cluster."
  type        = map(string)
  default     = {}
}

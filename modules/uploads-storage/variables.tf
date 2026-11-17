variable "name" {
  description = "Name prefix, e.g. looksmatter-production."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster that gets the EFS CSI driver add-on."
  type        = string
}

variable "vpc_id" {
  description = "VPC of the cluster."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets: one EFS mount target is created in each."
  type        = list(string)
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to mount the file system over NFS (the private subnets, where the nodes run). Must be known at plan time."
  type        = list(string)
}

variable "transition_to_ia" {
  description = "Move files nobody has read for this long to the cheaper Infrequent Access class."
  type        = string
  default     = "AFTER_30_DAYS"
}

variable "enable_backups" {
  description = "Daily AWS Backup snapshots of the uploads (35-day retention, AWS's default plan)."
  type        = bool
  default     = true
}

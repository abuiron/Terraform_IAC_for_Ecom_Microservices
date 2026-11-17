output "file_system_id" {
  description = "EFS file system id; the platform stack's StorageClass points at it."
  value       = aws_efs_file_system.uploads.id
}

output "security_group_id" {
  description = "Security group of the EFS mount targets."
  value       = aws_security_group.efs.id
}

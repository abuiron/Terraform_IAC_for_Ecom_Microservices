output "project_id" {
  description = "Atlas project id."
  value       = mongodbatlas_project.this.id
}

output "cluster_name" {
  description = "Atlas cluster name."
  value       = mongodbatlas_advanced_cluster.this.name
}

output "srv_host" {
  description = "Cluster host for mongodb+srv:// connection strings (not a secret)."
  value       = local.srv_host
}

output "database_usernames" {
  description = "Database user per service."
  value       = { for service, user in mongodbatlas_database_user.service : service => user.username }
}

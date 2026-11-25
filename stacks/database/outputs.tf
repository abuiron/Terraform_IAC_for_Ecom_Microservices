output "atlas_project_id" {
  description = "Atlas project id."
  value       = module.atlas.project_id
}

output "atlas_cluster_name" {
  description = "Atlas cluster name."
  value       = module.atlas.cluster_name
}

output "srv_host" {
  description = "Cluster host (connection strings with credentials are only in Secrets Manager)."
  value       = module.atlas.srv_host
}

output "database_usernames" {
  description = "Database user per service."
  value       = module.atlas.database_usernames
}

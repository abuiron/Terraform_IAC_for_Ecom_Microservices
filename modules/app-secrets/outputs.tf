output "prefix" {
  description = "Secret name prefix. The External Secrets Operator is allowed to read <prefix>/*."
  value       = var.prefix
}

output "secret_names" {
  description = "Secret names by purpose: shared, core-service, order-service, payment-gateway."
  value       = { for key, secret in aws_secretsmanager_secret.this : key => secret.name }
}

output "secret_arns" {
  description = "Secret ARNs by purpose."
  value       = { for key, secret in aws_secretsmanager_secret.this : key => secret.arn }
}

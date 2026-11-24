output "role_arn" {
  description = "Use as `role-to-assume` in aws-actions/configure-aws-credentials."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "IAM role name."
  value       = aws_iam_role.this.name
}

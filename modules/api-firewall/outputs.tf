output "web_acl_arn" {
  description = "ARN of the web ACL; set on the API ingress with the alb.ingress.kubernetes.io/wafv2-acl-arn annotation."
  value       = aws_wafv2_web_acl.this.arn
}

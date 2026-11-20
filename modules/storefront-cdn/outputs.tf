output "bucket_name" {
  description = "Bucket the storefront build is uploaded to."
  value       = aws_s3_bucket.site.bucket
}

output "bucket_arn" {
  description = "ARN of the storefront bucket."
  value       = aws_s3_bucket.site.arn
}

output "distribution_id" {
  description = "CloudFront distribution id (needed to invalidate the cache after a deploy)."
  value       = aws_cloudfront_distribution.site.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN."
  value       = aws_cloudfront_distribution.site.arn
}

output "distribution_domain_name" {
  description = "The *.cloudfront.net name, useful for testing before DNS points here."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "urls" {
  description = "Storefront URLs."
  value       = [for domain in var.domain_names : "https://${domain}"]
}

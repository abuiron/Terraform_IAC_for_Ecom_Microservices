# Storefront hosting: the React build (static files) in a private S3 bucket, served
# worldwide by CloudFront over HTTPS with the shop's own domains.
#
#   browser ──HTTPS──> CloudFront edge (cache, TLS, security headers) ──signed──> S3 bucket
#
# The bucket is not public: only this CloudFront distribution may read it (Origin Access
# Control). A static site needs no servers, so it is not in Kubernetes at all.

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------------------
# Bucket
# ---------------------------------------------------------------------------------------

resource "aws_s3_bucket" "site" {
  bucket = "${var.name}-storefront-${data.aws_caller_identity.current.account_id}"

  # The bucket only holds build output (rebuildable), but S3 refuses to delete a bucket
  # that still contains objects or old versions unless this is true.
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning lets you restore a previous deploy; old versions are cleaned up after 30 days.
resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    id     = "expire-old-deploys"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.site]
}

# ---------------------------------------------------------------------------------------
# TLS certificate (must live in us-east-1 for CloudFront), validated through Route 53
# ---------------------------------------------------------------------------------------

resource "aws_acm_certificate" "site" {
  provider = aws.us_east_1

  domain_name               = var.domain_names[0]
  subject_alternative_names = slice(var.domain_names, 1, length(var.domain_names))
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "site_validation" {
  for_each = {
    for option in aws_acm_certificate.site.domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  }

  zone_id         = var.hosted_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "site" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for record in aws_route53_record.site_validation : record.fqdn]
}

# ---------------------------------------------------------------------------------------
# CloudFront
# ---------------------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.name}-storefront"
  description                       = "CloudFront reads the storefront bucket with signed requests"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# AWS-managed policies: cache by URL with gzip/brotli, and standard security headers
# (HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy).
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_response_headers_policy" "security" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = "${var.name} storefront"
  aliases             = var.domain_names
  default_root_object = "index.html"
  price_class         = var.price_class
  http_version        = "http2and3"
  is_ipv6_enabled     = true

  origin {
    origin_id                = "storefront-bucket"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id           = "storefront-bucket"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  # Single-page app: paths like /product/42 exist only in the browser's router, so S3 has no
  # such file (403 with Origin Access Control, 404 otherwise). Answer with index.html and let
  # React Router render the page. This replaces Netlify's `/* /index.html 200` rule.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# Only this distribution may read the bucket, and only over TLS.
data "aws_iam_policy_document" "site" {
  statement {
    sid       = "AllowCloudFrontRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.site.arn,
      "${aws_s3_bucket.site.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site.json

  depends_on = [aws_s3_bucket_public_access_block.site]
}

# ---------------------------------------------------------------------------------------
# DNS: every storefront domain points at CloudFront (IPv4 and IPv6)
# ---------------------------------------------------------------------------------------

resource "aws_route53_record" "site" {
  for_each = {
    for pair in setproduct(var.domain_names, ["A", "AAAA"]) : "${pair[0]}/${pair[1]}" => {
      name = pair[0]
      type = pair[1]
    }
  }

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

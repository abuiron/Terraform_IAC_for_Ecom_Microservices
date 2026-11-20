terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      # CloudFront only accepts certificates from us-east-1, whatever region the rest is in.
      configuration_aliases = [aws.us_east_1]
    }
  }
}

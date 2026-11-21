terraform {
  # Write-only arguments (secret_string_wo) need Terraform 1.11+.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7" # 3.7 added the ephemeral random_password
    }
  }
}

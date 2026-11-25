provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "database"
    }
  }
}

# Credentials come from the environment, never from files:
#   MONGODB_ATLAS_CLIENT_ID / MONGODB_ATLAS_CLIENT_SECRET          (service account, recommended)
#   or MONGODB_ATLAS_PUBLIC_API_KEY / MONGODB_ATLAS_PRIVATE_API_KEY (programmatic API key)
provider "mongodbatlas" {}

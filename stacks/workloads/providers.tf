provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "workloads"
    }
  }
}

# Values published by the infrastructure stack (see stacks/infrastructure/contract.tf).
data "aws_ssm_parameter" "infrastructure" {
  name = "/${var.project}/${var.environment}/infrastructure"
}

locals {
  infra = jsondecode(data.aws_ssm_parameter.infrastructure.insecure_value)
}

data "aws_eks_cluster" "this" {
  name = local.infra.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.this.name, "--region", var.region]
  }
}

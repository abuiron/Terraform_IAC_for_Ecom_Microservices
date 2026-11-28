provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "platform"
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

# Both providers log in to the cluster the way kubectl does: a short-lived token from
# `aws eks get-token` (requires the AWS CLI where Terraform runs). Nothing is stored.
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.this.name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.this.name, "--region", var.region]
    }
  }
}

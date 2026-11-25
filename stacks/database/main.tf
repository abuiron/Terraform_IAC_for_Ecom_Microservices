# Database: MongoDB Atlas for one environment.
#
# Optional. Skip this stack if MongoDB is managed elsewhere; then store each service's
# connection string by hand (README → "Using an existing MongoDB").
#
# Kept apart from the infrastructure stack on purpose: data outlives clusters. Rebuilding or
# destroying the infrastructure must never be able to touch the database.

data "aws_ssm_parameter" "infrastructure" {
  name = "/${var.project}/${var.environment}/infrastructure"
}

locals {
  infra = jsondecode(data.aws_ssm_parameter.infrastructure.insecure_value)
  name  = "${var.project}-${var.environment}"

  # Every pod reaches the internet through the NAT gateways, so these are the only IPs
  # Atlas needs to accept (plus any admin IPs you add temporarily).
  allowed_cidrs = merge(
    { for index, ip in local.infra.nat_public_ips : "${local.name}-nat-${index + 1}" => "${ip}/32" },
    var.admin_access_cidrs,
  )
}

module "atlas" {
  source = "../../modules/mongodb-atlas"

  org_id       = var.atlas_org_id
  project_name = local.name
  cluster_name = local.name
  aws_region   = local.infra.region

  instance_size                  = var.instance_size
  max_instance_size              = var.max_instance_size
  mongo_db_major_version         = var.mongo_db_major_version
  backup_enabled                 = var.backup_enabled
  pit_enabled                    = var.pit_enabled
  termination_protection_enabled = var.termination_protection_enabled

  allowed_cidrs = local.allowed_cidrs

  # core-service → its database + its secret; order-service → its database + its secret.
  database_users = {
    for service, database in local.infra.databases : service => {
      database  = database
      secret_id = local.infra.secret_names[service]
    }
  }

  credentials_version = var.credentials_version

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

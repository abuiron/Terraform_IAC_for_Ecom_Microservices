# MongoDB Atlas: a 3-node replica set on AWS in the same region as the cluster, with
# backups, point-in-time restore, and compute and disk auto-scaling.
#
# Database per service: each service gets its own database user that can read and write
# only its own database. That enforces the microservice boundary in the database itself,
# not only by convention:
#
#   core-service   → readWrite on "looksmatter"
#   order-service  → readWrite on "looksmatter_orders"

locals {
  atlas_region = upper(replace(var.aws_region, "-", "_")) # ap-south-1 → AP_SOUTH_1

  # Atlas returns "mongodb+srv://<cluster>.<id>.mongodb.net"; keep only the host.
  srv_host = trimprefix(mongodbatlas_advanced_cluster.this.connection_strings.standard_srv, "mongodb+srv://")
}

resource "mongodbatlas_project" "this" {
  name   = var.project_name
  org_id = var.org_id
  tags   = var.tags
}

# Network access: only the listed CIDRs (the NAT gateway IPs of the VPC, plus any admin IPs).
resource "mongodbatlas_project_ip_access_list" "this" {
  for_each = var.allowed_cidrs

  project_id = mongodbatlas_project.this.id
  cidr_block = each.value
  comment    = each.key
}

resource "mongodbatlas_advanced_cluster" "this" {
  project_id                     = mongodbatlas_project.this.id
  name                           = var.cluster_name
  cluster_type                   = "REPLICASET"
  mongo_db_major_version         = var.mongo_db_major_version
  backup_enabled                 = var.backup_enabled
  pit_enabled                    = var.pit_enabled
  termination_protection_enabled = var.termination_protection_enabled

  replication_specs = [
    {
      region_configs = [
        {
          provider_name = "AWS"
          region_name   = local.atlas_region
          priority      = 7

          # Three electable nodes: if the primary fails, another is elected within seconds.
          electable_specs = {
            instance_size = var.instance_size
            node_count    = 3
          }

          auto_scaling = {
            compute_enabled            = true
            compute_scale_down_enabled = true
            compute_min_instance_size  = var.instance_size
            compute_max_instance_size  = var.max_instance_size
            disk_gb_enabled            = true
          }
        }
      ]
    }
  ]

  advanced_configuration = {
    javascript_enabled           = false # no server-side JavaScript: smaller attack surface
    minimum_enabled_tls_protocol = "TLS1_2"
  }

  tags = var.tags

  lifecycle {
    # Auto-scaling changes the tier itself; without this, every apply would try to undo it.
    ignore_changes = [
      replication_specs[0].region_configs[0].electable_specs.instance_size,
    ]
  }
}

# Passwords are ephemeral: generated during the run, sent to Atlas and Secrets Manager via
# write-only arguments, and never stored in Terraform state.
ephemeral "random_password" "database_user" {
  for_each = var.database_users

  length  = 32
  special = false # letters and digits only, so the password needs no escaping in a URI
}

resource "mongodbatlas_database_user" "service" {
  for_each = var.database_users

  project_id          = mongodbatlas_project.this.id
  username            = "${var.cluster_name}-${each.key}"
  password_wo         = ephemeral.random_password.database_user[each.key].result
  password_wo_version = var.credentials_version
  auth_database_name  = "admin"

  roles {
    role_name     = "readWrite"
    database_name = each.value.database
  }

  scopes {
    name = mongodbatlas_advanced_cluster.this.name
    type = "CLUSTER"
  }
}

# MONGO_URI for each service, written straight into its Secrets Manager secret.
resource "aws_secretsmanager_secret_version" "mongo_uri" {
  for_each = var.database_users

  secret_id = each.value.secret_id

  secret_string_wo = jsonencode({
    MONGO_URI = "mongodb+srv://${mongodbatlas_database_user.service[each.key].username}:${ephemeral.random_password.database_user[each.key].result}@${local.srv_host}/?retryWrites=true&w=majority&appName=${each.key}"
  })
  secret_string_wo_version = var.credentials_version
}

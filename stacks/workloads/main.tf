# Workloads: the looksmatter backend on Kubernetes.
#
#   internet → ALB (TLS, WAF) → gateway ─┬─> core-service  ─> MongoDB "looksmatter"  + EFS uploads
#                                        └─> order-service ─> MongoDB "looksmatter_orders"
#
# Only the gateway is reachable from outside. core-service and order-service are
# ClusterIP Services: reachable inside the cluster only, exactly like the private
# network in docker-compose.

locals {
  namespace     = var.namespace
  service_names = ["gateway", "core-service", "order-service"]

  # Cluster-internal addresses. The same ports as local development, so nothing in the
  # services' configuration changes shape.
  internal_url = {
    "core-service"  = "http://core-service.${local.namespace}.svc.cluster.local:5001"
    "order-service" = "http://order-service.${local.namespace}.svc.cluster.local:5002"
  }

  image_tags = { for name in local.service_names : name => lookup(var.image_tag_overrides, name, var.image_tag) }

  # repo:tag@sha256:digest. The digest pins the exact image that was resolved at plan time;
  # the tag stays for humans reading `kubectl describe`.
  images = {
    for name in local.service_names :
    name => "${data.aws_ecr_repository.service[name].repository_url}:${local.image_tags[name]}@${data.aws_ecr_image.service[name].image_digest}"
  }

  cors_origins = join(",", concat(
    [for domain in local.infra.storefront_domains : "https://${domain}"],
    var.extra_cors_origins,
  ))

  # Node.js decides its heap size on its own; tie it to the container's memory limit so the
  # garbage collector works before Kubernetes kills the pod for using too much memory.
  node_options = {
    for name, service in var.services :
    name => "--max-old-space-size=${floor(tonumber(trimsuffix(service.memory_limit, "Mi")) * 0.75)}"
  }

  # Which Secrets Manager secrets make up each service's Kubernetes Secret.
  secret_sources = {
    "core-service"  = ["shared", "core-service"]
    "order-service" = ["shared", "order-service", "payment-gateway"]
  }
}

# ---------------------------------------------------------------------------------------
# Images: fail at plan time if a tag was never pushed, instead of pods stuck pulling.
# ---------------------------------------------------------------------------------------

data "aws_ecr_repository" "service" {
  for_each = toset(local.service_names)

  name = "${var.project}/${each.key}"
}

data "aws_ecr_image" "service" {
  for_each = toset(local.service_names)

  repository_name = data.aws_ecr_repository.service[each.key].name
  image_tag       = local.image_tags[each.key]
}

# ---------------------------------------------------------------------------------------
# Namespace with the "restricted" Pod Security Standard: Kubernetes rejects any pod in it
# that runs as root, can escalate privileges or keeps Linux capabilities.
# ---------------------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = local.namespace

    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

# ---------------------------------------------------------------------------------------
# Secrets: Secrets Manager → External Secrets Operator → Kubernetes Secret → env vars
# ---------------------------------------------------------------------------------------

resource "kubernetes_manifest" "secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "SecretStore"

    metadata = {
      name      = "aws-secrets-manager"
      namespace = kubernetes_namespace_v1.app.metadata[0].name
    }

    # No `auth` block: the operator uses its own EKS Pod Identity role (platform stack),
    # which may read only this environment's secrets.
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
        }
      }
    }
  }
}

resource "kubernetes_manifest" "external_secret" {
  for_each = local.secret_sources

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"

    metadata = {
      name      = each.key
      namespace = kubernetes_namespace_v1.app.metadata[0].name
    }

    spec = {
      refreshInterval = "1h0m0s"

      secretStoreRef = {
        kind = "SecretStore"
        name = "aws-secrets-manager"
      }

      target = {
        name           = "${each.key}-secrets"
        creationPolicy = "Owner"
      }

      # Each Secrets Manager secret is a JSON object; every key becomes one entry.
      dataFrom = [
        for source in each.value : {
          extract = {
            key = local.infra.secret_names[source]
          }
        }
      ]
    }
  }

  # Don't start the services until their secrets are in place. If this times out, a secret
  # is missing a value: usually the payment-gateway one (README → "Step 5").
  wait {
    condition {
      type   = "Ready"
      status = "True"
    }
  }

  timeouts {
    create = "3m"
    update = "3m"
  }

  depends_on = [kubernetes_manifest.secret_store]
}

# ---------------------------------------------------------------------------------------
# Shared uploads folder (EFS, ReadWriteMany): every core-service pod sees the same files.
# ---------------------------------------------------------------------------------------

resource "kubernetes_persistent_volume_claim_v1" "uploads" {
  metadata {
    name      = "core-service-uploads"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "efs-uploads"

    resources {
      requests = {
        storage = var.uploads_volume_size
      }
    }
  }

  wait_until_bound = true
}

# ---------------------------------------------------------------------------------------
# The three services
# ---------------------------------------------------------------------------------------

module "gateway" {
  source = "../../modules/k8s-microservice"

  name           = "gateway"
  namespace      = kubernetes_namespace_v1.app.metadata[0].name
  image          = local.images["gateway"]
  port           = 5000
  readiness_path = "/" # not /health: that one reports on the other services too

  # The load balancer health-checks new pods on its own (2 checks, 10 s apart). Keep each
  # new gateway pod 30 s in the rollout before an old one stops, so the load balancer
  # always has healthy targets during a release.
  min_ready_seconds = 30

  env = {
    NODE_ENV          = "production"
    PORT              = "5000"
    CORE_SERVICE_URL  = local.internal_url["core-service"]
    ORDER_SERVICE_URL = local.internal_url["order-service"]
    CORS_ORIGINS      = local.cors_origins
    PROXY_TIMEOUT_MS  = tostring(var.proxy_timeout_ms)
    NODE_OPTIONS      = local.node_options["gateway"]
  }

  resources = {
    cpu_request    = var.services["gateway"].cpu_request
    memory_request = var.services["gateway"].memory_request
    memory_limit   = var.services["gateway"].memory_limit
  }

  autoscaling = {
    min_replicas           = var.services["gateway"].min_replicas
    max_replicas           = var.services["gateway"].max_replicas
    target_cpu_utilization = var.services["gateway"].target_cpu
  }
}

module "core_service" {
  source = "../../modules/k8s-microservice"

  name           = "core-service"
  namespace      = kubernetes_namespace_v1.app.metadata[0].name
  image          = local.images["core-service"]
  port           = 5001
  readiness_path = "/health"
  secret_name    = "core-service-secrets" # JWT_SECRET, INTERNAL_API_KEY, MONGO_URI

  env = {
    NODE_ENV          = "production"
    PORT              = "5001"
    MONGO_DB          = local.infra.databases["core-service"]
    ORDER_SERVICE_URL = local.internal_url["order-service"]
    NODE_OPTIONS      = local.node_options["core-service"]
  }

  # Product images uploaded through the admin panel.
  volume = {
    claim_name = kubernetes_persistent_volume_claim_v1.uploads.metadata[0].name
    mount_path = "/app/uploads"
  }

  resources = {
    cpu_request    = var.services["core-service"].cpu_request
    memory_request = var.services["core-service"].memory_request
    memory_limit   = var.services["core-service"].memory_limit
  }

  autoscaling = {
    min_replicas           = var.services["core-service"].min_replicas
    max_replicas           = var.services["core-service"].max_replicas
    target_cpu_utilization = var.services["core-service"].target_cpu
  }

  depends_on = [kubernetes_manifest.external_secret]
}

module "order_service" {
  source = "../../modules/k8s-microservice"

  name           = "order-service"
  namespace      = kubernetes_namespace_v1.app.metadata[0].name
  image          = local.images["order-service"]
  port           = 5002
  readiness_path = "/health"
  secret_name    = "order-service-secrets" # JWT_SECRET, INTERNAL_API_KEY, MONGO_URI, PaymentGateway_*

  env = {
    NODE_ENV                    = "production"
    PORT                        = "5002"
    MONGO_DB                    = local.infra.databases["order-service"]
    CORE_SERVICE_URL            = local.internal_url["core-service"]
    PaymentGateway_CALLBACK_URL = "https://${local.infra.api_domain}${var.payment_webhook_path}"
    NODE_OPTIONS                = local.node_options["order-service"]
  }

  resources = {
    cpu_request    = var.services["order-service"].cpu_request
    memory_request = var.services["order-service"].memory_request
    memory_limit   = var.services["order-service"].memory_limit
  }

  autoscaling = {
    min_replicas           = var.services["order-service"].min_replicas
    max_replicas           = var.services["order-service"].max_replicas
    target_cpu_utilization = var.services["order-service"].target_cpu
  }

  depends_on = [kubernetes_manifest.external_secret]
}

# ---------------------------------------------------------------------------------------
# Public entry point: Ingress → Application Load Balancer → gateway pods
# ---------------------------------------------------------------------------------------

resource "kubernetes_ingress_v1" "api" {
  metadata {
    name      = "api"
    namespace = kubernetes_namespace_v1.app.metadata[0].name

    annotations = merge(
      {
        # HTTP is only kept to redirect to HTTPS.
        "alb.ingress.kubernetes.io/listen-ports" = jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
        "alb.ingress.kubernetes.io/ssl-redirect" = "443"

        # Send traffic straight to pod IPs (no extra hop through the nodes).
        "alb.ingress.kubernetes.io/target-type" = "ip"

        # The gateway's "/" answers without asking the other services, so one sick
        # service never makes the load balancer drop every gateway pod.
        "alb.ingress.kubernetes.io/healthcheck-path"             = "/"
        "alb.ingress.kubernetes.io/success-codes"                = "200"
        "alb.ingress.kubernetes.io/healthcheck-interval-seconds" = "10"
        "alb.ingress.kubernetes.io/healthy-threshold-count"      = "2"
        "alb.ingress.kubernetes.io/unhealthy-threshold-count"    = "2"

        # Matches the pods' 30-second shutdown window (the default is 300 seconds).
        "alb.ingress.kubernetes.io/target-group-attributes" = "deregistration_delay.timeout_seconds=30"
      },
      local.infra.waf_web_acl_arn == null ? {} : {
        "alb.ingress.kubernetes.io/wafv2-acl-arn" = local.infra.waf_web_acl_arn
      },
    )
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = local.infra.api_domain

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = module.gateway.service_name

              port {
                number = module.gateway.service_port
              }
            }
          }
        }
      }
    }
  }

  # Wait until AWS has created the load balancer, so its hostname can go into DNS below.
  wait_for_load_balancer = true
}

data "aws_lb_hosted_zone_id" "alb" {}

resource "aws_route53_record" "api" {
  zone_id = local.infra.hosted_zone_id
  name    = local.infra.api_domain
  type    = "A"

  alias {
    name                   = kubernetes_ingress_v1.api.status[0].load_balancer[0].ingress[0].hostname
    zone_id                = data.aws_lb_hosted_zone_id.alb.id
    evaluate_target_health = true
  }
}

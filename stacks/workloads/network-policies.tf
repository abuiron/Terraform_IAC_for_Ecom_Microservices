# Network policies: a firewall between pods.
#
# Without them every pod in the cluster can call every other pod. With them:
#
#   anyone (the ALB)          → gateway:5000
#   gateway, order-service    → core-service:5001    (public routes + checkout's internal calls)
#   gateway, core-service     → order-service:5002   (public routes + support reports' internal calls)
#   everything else           → blocked
#
# This is defense in depth for the /internal routes, which are also protected by
# INTERNAL_API_KEY. Kubelet health probes come from the node and are always allowed.

resource "kubernetes_network_policy_v1" "default_deny_ingress" {
  count = var.enable_network_policies ? 1 : 0

  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy_v1" "gateway" {
  count = var.enable_network_policies ? 1 : 0

  metadata {
    name      = "gateway-from-anywhere"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "gateway"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      ports {
        port     = "5000"
        protocol = "TCP"
      }
    }
  }
}

locals {
  allowed_callers = {
    "core-service"  = { port = 5001, from = ["gateway", "order-service"] }
    "order-service" = { port = 5002, from = ["gateway", "core-service"] }
  }
}

resource "kubernetes_network_policy_v1" "service" {
  for_each = var.enable_network_policies ? local.allowed_callers : {}

  metadata {
    name      = "${each.key}-allowed-callers"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = each.key
      }
    }

    policy_types = ["Ingress"]

    ingress {
      ports {
        port     = tostring(each.value.port)
        protocol = "TCP"
      }

      dynamic "from" {
        for_each = each.value.from

        content {
          pod_selector {
            match_labels = {
              "app.kubernetes.io/name" = from.value
            }
          }
        }
      }
    }
  }
}

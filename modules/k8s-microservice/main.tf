# One microservice on Kubernetes, with production defaults:
#
#   ServiceAccount            its own identity (no Kubernetes API token mounted)
#   Deployment                the pods: probes, zero-downtime rolling updates, hardened security context
#   Service                   stable DNS name and load balancing across the pods
#   HorizontalPodAutoscaler   adds/removes pods with CPU load
#   PodDisruptionBudget       keeps pods running while nodes are drained or replaced
#
# The workloads stack calls this module once per service.

locals {
  # Selector labels must never change after the first deploy (Kubernetes forbids it).
  selector_labels = {
    "app.kubernetes.io/name" = var.name
  }

  labels = merge(local.selector_labels, {
    "app.kubernetes.io/part-of"    = var.part_of
    "app.kubernetes.io/managed-by" = "terraform"
  })
}

resource "kubernetes_service_account_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  # The apps never call the Kubernetes API, so they get no token to steal.
  automount_service_account_token = false
}

resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    replicas                  = var.autoscaling.min_replicas
    revision_history_limit    = 5
    progress_deadline_seconds = 600
    min_ready_seconds         = var.min_ready_seconds

    selector {
      match_labels = local.selector_labels
    }

    # Zero downtime: start a new pod, wait until it is ready, then stop an old one.
    strategy {
      type = "RollingUpdate"

      rolling_update {
        max_surge       = "25%"
        max_unavailable = "0"
      }
    }

    template {
      metadata {
        labels = local.labels

        annotations = {
          # Changing any setting changes this hash, which rolls the pods so they pick it up.
          "looksmatter.in/config-hash" = sha1(jsonencode(var.env))
        }
      }

      spec {
        service_account_name             = kubernetes_service_account_v1.this.metadata[0].name
        automount_service_account_token  = false
        termination_grace_period_seconds = var.termination_grace_period_seconds

        # Matches the `node` user (uid 1000) the Dockerfiles switch to.
        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          run_as_group    = 1000
          fs_group        = 1000

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        # Spread pods across zones, then across nodes, so one failure can't take them all.
        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "topology.kubernetes.io/zone"
          when_unsatisfiable = "ScheduleAnyway"

          label_selector {
            match_labels = local.selector_labels
          }
        }

        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "kubernetes.io/hostname"
          when_unsatisfiable = "ScheduleAnyway"

          label_selector {
            match_labels = local.selector_labels
          }
        }

        container {
          name              = var.name
          image             = var.image
          image_pull_policy = "IfNotPresent"

          port {
            name           = "http"
            container_port = var.port
            protocol       = "TCP"
          }

          dynamic "env" {
            for_each = var.env

            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "env_from" {
            for_each = var.secret_name == null ? [] : [var.secret_name]

            content {
              secret_ref {
                name = env_from.value
              }
            }
          }

          resources {
            requests = {
              cpu    = var.resources.cpu_request
              memory = var.resources.memory_request
            }

            limits = {
              memory = var.resources.memory_limit
            }
          }

          # The services only start listening once MongoDB is connected. Allow up to
          # 2 minutes for that before Kubernetes gives up and restarts the pod.
          startup_probe {
            tcp_socket {
              port = var.port
            }

            period_seconds    = 2
            failure_threshold = 60
          }

          # Ready = may receive traffic. core/order answer 503 on /health while MongoDB is
          # unreachable, which takes the pod out of the Service until it recovers.
          readiness_probe {
            http_get {
              path = var.readiness_path
              port = var.port
            }

            period_seconds    = 5
            timeout_seconds   = 3
            failure_threshold = 3
          }

          # Alive = the process is listening. Deliberately NOT /health: a database outage
          # must not make Kubernetes restart every pod in a loop.
          liveness_probe {
            tcp_socket {
              port = var.port
            }

            period_seconds    = 10
            timeout_seconds   = 3
            failure_threshold = 3
          }

          # Kubernetes removes a stopping pod from load balancing and sends SIGTERM at the
          # same time. Sleeping first gives the load balancer time to stop sending requests.
          lifecycle {
            pre_stop {
              exec {
                command = ["sleep", tostring(var.pre_stop_sleep_seconds)]
              }
            }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true

            capabilities {
              drop = ["ALL"]
            }
          }

          # The root filesystem is read-only; /tmp is the one scratch area.
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          dynamic "volume_mount" {
            for_each = var.volume == null ? [] : [var.volume]

            content {
              name       = "data"
              mount_path = volume_mount.value.mount_path
            }
          }
        }

        volume {
          name = "tmp"

          empty_dir {
            size_limit = "64Mi"
          }
        }

        dynamic "volume" {
          for_each = var.volume == null ? [] : [var.volume]

          content {
            name = "data"

            persistent_volume_claim {
              claim_name = volume.value.claim_name
            }
          }
        }
      }
    }
  }

  # Terraform waits until the new pods are ready, so a broken release fails the apply.
  wait_for_rollout = true

  timeouts {
    create = "10m"
    update = "10m"
  }

  lifecycle {
    # After the first apply the HorizontalPodAutoscaler owns the replica count.
    ignore_changes = [spec[0].replicas]
  }
}

resource "kubernetes_service_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    type     = "ClusterIP"
    selector = local.selector_labels

    port {
      name        = "http"
      port        = var.port
      target_port = "http"
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    min_replicas = var.autoscaling.min_replicas
    max_replicas = var.autoscaling.max_replicas

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.this.metadata[0].name
    }

    metric {
      type = "Resource"

      resource {
        name = "cpu"

        target {
          type                = "Utilization"
          average_utilization = var.autoscaling.target_cpu_utilization
        }
      }
    }

    # Scale up fast (a sale starts), scale down slowly (traffic often comes back).
    behavior {
      scale_up {
        stabilization_window_seconds = 0
        select_policy                = "Max"

        policy {
          type           = "Percent"
          value          = 100
          period_seconds = 30
        }

        policy {
          type           = "Pods"
          value          = 4
          period_seconds = 30
        }
      }

      scale_down {
        stabilization_window_seconds = 300
        select_policy                = "Max"

        policy {
          type           = "Percent"
          value          = 50
          period_seconds = 60
        }
      }
    }
  }
}

resource "kubernetes_pod_disruption_budget_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    # Node replacements (upgrades, consolidation) evict at most one pod of this service at a time.
    max_unavailable = "1"

    selector {
      match_labels = local.selector_labels
    }
  }
}

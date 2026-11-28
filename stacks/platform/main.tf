# Platform: cluster-wide building blocks the application relies on.
#
#   NodePool "looksmatter-apps"   how nodes autoscale for the apps (instance types, spot, cost ceiling)
#   IngressClass "alb"            Ingress → AWS Application Load Balancer, with TLS and the WAF
#   StorageClass "efs-uploads"    ReadWriteMany volumes on the EFS file system
#   NetworkPolicy enforcement     lets the workloads stack restrict pod-to-pod traffic
#   metrics-server                CPU/memory metrics; the HorizontalPodAutoscalers need them
#   External Secrets Operator     copies Secrets Manager values into Kubernetes Secrets
#
# Separate from the workloads stack because the workloads use custom resources
# (ExternalSecret, SecretStore) whose definitions are installed here. Terraform can only
# plan a custom resource once its definition exists in the cluster.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ---------------------------------------------------------------------------------------
# Node autoscaling
# ---------------------------------------------------------------------------------------
# EKS Auto Mode runs Karpenter for us. When pods can't be scheduled (e.g. the autoscaler
# added replicas), it picks the cheapest instance that fits from the NodePools allowed for
# them, launches it in about a minute, and later removes or replaces nodes that are empty
# or underused (consolidation). Higher weight = preferred; the built-in "general-purpose"
# pool stays as a fallback for anything this pool can't serve.

resource "kubernetes_manifest" "app_node_pool" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"

    metadata = {
      name = "looksmatter-apps"
    }

    spec = {
      weight = 50

      template = {
        metadata = {
          labels = {
            "looksmatter.in/node-pool" = "apps"
          }
        }

        spec = {
          # Reuse the NodeClass Auto Mode creates (subnets, security group, node IAM role).
          nodeClassRef = {
            group = "eks.amazonaws.com"
            kind  = "NodeClass"
            name  = "default"
          }

          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = var.node_capacity_types
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = var.node_architectures
            },
            {
              key      = "eks.amazonaws.com/instance-category"
              operator = "In"
              values   = var.node_instance_categories
            },
            {
              key      = "eks.amazonaws.com/instance-generation"
              operator = "Gt"
              values   = [tostring(var.node_min_generation)]
            },
          ]

          # Replace every node at least every 14 days, so nodes always run recent, patched images.
          expireAfter = "336h"
        }
      }

      # Hard ceiling: the pool never grows beyond this, whatever the load.
      limits = {
        cpu    = tostring(var.node_pool_cpu_limit)
        memory = "${var.node_pool_memory_limit_gib}Gi"
      }

      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = var.node_consolidate_after

        # Voluntary node replacements touch at most 10% of nodes at a time.
        budgets = [
          {
            nodes = "10%"
          },
        ]
      }
    }
  }
}

# ---------------------------------------------------------------------------------------
# Ingress → Application Load Balancer
# ---------------------------------------------------------------------------------------
# With Auto Mode, load balancer settings live in an IngressClassParams object; annotations
# on the IngressClass itself are not supported.

resource "kubernetes_manifest" "alb_params" {
  manifest = {
    apiVersion = "eks.amazonaws.com/v1"
    kind       = "IngressClassParams"

    metadata = {
      name = "looksmatter-alb"
    }

    spec = {
      scheme          = "internet-facing"
      ipAddressType   = "ipv4"
      certificateARNs = [local.infra.api_certificate_arn]
      sslPolicy       = var.alb_ssl_policy

      # Put the load balancer in the public subnets explicitly instead of relying on discovery.
      subnets = {
        ids = local.infra.public_subnet_ids
      }

      loadBalancerAttributes = [
        {
          key   = "idle_timeout.timeout_seconds"
          value = "60"
        },
        {
          # Drop requests with malformed headers (request smuggling protection).
          key   = "routing.http.drop_invalid_header_fields.enabled"
          value = "true"
        },
      ]
    }
  }
}

resource "kubernetes_ingress_class_v1" "alb" {
  metadata {
    name = "alb"

    annotations = {
      "ingressclass.kubernetes.io/is-default-class" = "true"
    }
  }

  spec {
    controller = "eks.amazonaws.com/alb"

    parameters {
      api_group = "eks.amazonaws.com"
      kind      = "IngressClassParams"
      name      = "looksmatter-alb"
    }
  }

  depends_on = [kubernetes_manifest.alb_params]
}

# ---------------------------------------------------------------------------------------
# Storage for uploads
# ---------------------------------------------------------------------------------------
# Each claim gets its own EFS access point. The access point forces uid/gid 1000 (the
# `node` user in the images), so the app can write without running as root.

resource "kubernetes_storage_class_v1" "efs_uploads" {
  metadata {
    name = "efs-uploads"
  }

  storage_provisioner = "efs.csi.aws.com"
  reclaim_policy      = "Retain" # deleting the claim never deletes the files
  volume_binding_mode = "Immediate"

  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = local.infra.uploads_file_system_id
    directoryPerms   = "700"
    uid              = "1000"
    gid              = "1000"
    basePath         = "/looksmatter"
  }
}

# ---------------------------------------------------------------------------------------
# NetworkPolicy enforcement
# ---------------------------------------------------------------------------------------
# Auto Mode ships the network policy agent switched off; this ConfigMap turns it on.
# If it already exists in your cluster, import it instead:
#   terraform import 'kubernetes_config_map_v1.network_policy[0]' kube-system/amazon-vpc-cni

resource "kubernetes_config_map_v1" "network_policy" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "amazon-vpc-cni"
    namespace = "kube-system"
  }

  data = {
    "enable-network-policy-controller" = "true"
  }
}

# ---------------------------------------------------------------------------------------
# metrics-server: the HorizontalPodAutoscalers read pod CPU usage from it
# ---------------------------------------------------------------------------------------

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version
  namespace  = "kube-system"

  wait    = true
  timeout = 600

  values = [yamlencode({
    replicas = 2

    podDisruptionBudget = {
      enabled      = true
      minAvailable = 1
    }

    resources = {
      requests = {
        cpu    = "50m"
        memory = "100Mi"
      }
    }
  })]

  depends_on = [kubernetes_manifest.app_node_pool]
}

# ---------------------------------------------------------------------------------------
# External Secrets Operator
# ---------------------------------------------------------------------------------------
# Reads <project>/<environment>/* from Secrets Manager and writes Kubernetes Secrets. It
# gets AWS access through EKS Pod Identity: an IAM role bound to its service account.

data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${var.project}-${var.environment}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

# Read-only, and only this environment's secrets.
data "aws_iam_policy_document" "external_secrets" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${local.infra.secrets_prefix}/*",
    ]
  }
}

resource "aws_iam_role_policy" "external_secrets" {
  name   = "read-${var.environment}-secrets"
  role   = aws_iam_role.external_secrets.id
  policy = data.aws_iam_policy_document.external_secrets.json
}

# Must exist before the operator's pod starts, so the pod receives the credentials.
resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = local.infra.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets.arn
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  namespace        = "external-secrets"
  create_namespace = true

  wait    = true
  timeout = 600

  values = [yamlencode({
    installCRDs = true

    serviceAccount = {
      create = true
      name   = "external-secrets"
    }

    resources = {
      requests = {
        cpu    = "50m"
        memory = "128Mi"
      }
    }

    webhook = {
      resources = {
        requests = {
          cpu    = "25m"
          memory = "64Mi"
        }
      }
    }

    certController = {
      resources = {
        requests = {
          cpu    = "25m"
          memory = "64Mi"
        }
      }
    }
  })]

  depends_on = [
    aws_eks_pod_identity_association.external_secrets,
    aws_iam_role_policy.external_secrets,
    kubernetes_manifest.app_node_pool,
  ]
}

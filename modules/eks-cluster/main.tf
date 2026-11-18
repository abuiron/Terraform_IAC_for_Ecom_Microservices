# EKS cluster in Auto Mode.
#
# Auto Mode means AWS runs the parts of Kubernetes that every cluster needs and nobody wants
# to babysit: it launches, patches and removes the EC2 nodes (node autoscaling), and it runs
# the pod networking, DNS, block storage and load balancer controllers. We still decide what
# runs on the cluster and how it scales; the platform stack tunes the node autoscaling.

data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition
}

# ---------------------------------------------------------------------------------------
# Encryption key for Kubernetes Secrets (envelope encryption in etcd)
# ---------------------------------------------------------------------------------------

resource "aws_kms_key" "eks" {
  description             = "${var.name}: envelope encryption for Kubernetes Secrets"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# ---------------------------------------------------------------------------------------
# IAM role the EKS control plane uses. Auto Mode needs the compute, storage, load
# balancing and networking policies on top of the classic cluster policy.
# ---------------------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = toset([
    "AmazonEKSClusterPolicy",
    "AmazonEKSComputePolicy",
    "AmazonEKSBlockStoragePolicy",
    "AmazonEKSLoadBalancingPolicy",
    "AmazonEKSNetworkingPolicy",
  ])

  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.key}"
}

data "aws_iam_policy_document" "cluster_kms" {
  statement {
    effect    = "Allow"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ListGrants", "kms:DescribeKey"]
    resources = [aws_kms_key.eks.arn]
  }
}

resource "aws_iam_role_policy" "cluster_kms" {
  name   = "secrets-envelope-encryption"
  role   = aws_iam_role.cluster.id
  policy = data.aws_iam_policy_document.cluster_kms.json
}

# ---------------------------------------------------------------------------------------
# IAM role for the EC2 nodes Auto Mode launches. Deliberately minimal: pods that need AWS
# access get their own role through EKS Pod Identity instead of borrowing the node's.
# ---------------------------------------------------------------------------------------

data "aws_iam_policy_document" "node_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodeMinimalPolicy",
    "AmazonEC2ContainerRegistryPullOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.key}"
}

# ---------------------------------------------------------------------------------------
# The cluster
# ---------------------------------------------------------------------------------------

# Created before the cluster so we own its retention; otherwise EKS creates one that never expires.
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.log_retention_days
}

resource "aws_eks_cluster" "this" {
  name                = var.name
  version             = var.kubernetes_version
  role_arn            = aws_iam_role.cluster.arn
  deletion_protection = var.deletion_protection

  # Access is granted with EKS access entries (below), not the old aws-auth ConfigMap.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Auto Mode installs and manages networking, DNS and kube-proxy itself.
  bootstrap_self_managed_addons = false

  # The three Auto Mode switches must be on together.
  compute_config {
    enabled       = true
    node_pools    = var.built_in_node_pools
    node_role_arn = aws_iam_role.node.arn
  }

  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true
    }
  }

  storage_config {
    block_storage {
      enabled = true
    }
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.endpoint_public_access_cidrs
  }

  encryption_config {
    resources = ["secrets"]

    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  enabled_cluster_log_types = var.enabled_log_types

  # STANDARD: when a version leaves standard support, EKS upgrades the cluster instead of
  # moving it to extended support, which costs several times more per hour.
  upgrade_policy {
    support_type = "STANDARD"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_iam_role_policy.cluster_kms,
    aws_cloudwatch_log_group.cluster,
  ]
}

# ---------------------------------------------------------------------------------------
# Who may use kubectl: extra cluster admins (people, CI roles)
# ---------------------------------------------------------------------------------------

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

# ---------------------------------------------------------------------------------------
# Container Insights: container logs (Fluent Bit) and metrics in CloudWatch.
# The agent gets AWS permissions through EKS Pod Identity, not through the node role.
# ---------------------------------------------------------------------------------------

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

resource "aws_iam_role" "cloudwatch_agent" {
  count = var.enable_container_insights ? 1 : 0

  name               = "${var.name}-cloudwatch-agent"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  count = var.enable_container_insights ? 1 : 0

  role       = aws_iam_role.cloudwatch_agent[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_eks_addon" "cloudwatch_observability" {
  count = var.enable_container_insights ? 1 : 0

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  pod_identity_association {
    role_arn        = aws_iam_role.cloudwatch_agent[0].arn
    service_account = "cloudwatch-agent"
  }

  depends_on = [aws_iam_role_policy_attachment.cloudwatch_agent]
}

# Shared storage for product images uploaded through the admin panel.
#
# core-service writes uploads to its local disk (/app/uploads). In Kubernetes there are
# several core-service pods on different nodes, and pods are replaced all the time, so a
# local disk would lose files and each pod would see different ones. Amazon EFS is a
# network file system every pod can mount at the same time (ReadWriteMany), in every zone,
# so the app keeps working without code changes. (Moving uploads to S3 is the long-term
# fix; see README → "App changes worth making".)

data "aws_partition" "current" {}

resource "aws_efs_file_system" "uploads" {
  creation_token   = "${var.name}-uploads"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic" # scales throughput with load; pay for what is used

  lifecycle_policy {
    transition_to_ia = var.transition_to_ia
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = {
    Name = "${var.name}-uploads"
  }
}

resource "aws_efs_backup_policy" "uploads" {
  file_system_id = aws_efs_file_system.uploads.id

  backup_policy {
    status = var.enable_backups ? "ENABLED" : "DISABLED"
  }
}

resource "aws_security_group" "efs" {
  name        = "${var.name}-efs-uploads"
  description = "NFS from the private subnets to the uploads file system"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-efs-uploads"
  }
}

resource "aws_vpc_security_group_ingress_rule" "nfs" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = aws_security_group.efs.id
  description       = "NFS from ${each.value}"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 2049
  to_port           = 2049
}

resource "aws_efs_mount_target" "uploads" {
  count = length(var.subnet_ids)

  file_system_id  = aws_efs_file_system.uploads.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# ---------------------------------------------------------------------------------------
# EFS CSI driver: lets Kubernetes create and mount EFS volumes. Its controller creates an
# EFS access point per volume, so it gets AWS permissions through EKS Pod Identity.
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

resource "aws_iam_role" "efs_csi" {
  name               = "${var.name}-efs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy_attachment" "efs_csi" {
  role       = aws_iam_role.efs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

resource "aws_eks_addon" "efs_csi" {
  cluster_name                = var.cluster_name
  addon_name                  = "aws-efs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  pod_identity_association {
    role_arn        = aws_iam_role.efs_csi.arn
    service_account = "efs-csi-controller-sa"
  }

  depends_on = [
    aws_iam_role_policy_attachment.efs_csi,
    aws_efs_mount_target.uploads,
  ]
}

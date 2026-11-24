# An IAM role GitHub Actions can assume without any stored AWS keys.
#
# GitHub signs a short-lived OIDC token for each workflow run. AWS checks the signature and
# the claims below (which repository, which branch or environment), then hands out
# temporary credentials for this role only. Nothing long-lived to leak or rotate.

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = concat(
        [for branch in var.branches : "repo:${var.repository}:ref:refs/heads/${branch}"],
        [for environment in var.environments : "repo:${var.repository}:environment:${environment}"],
      )
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.name
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = var.max_session_duration

  lifecycle {
    precondition {
      condition     = length(var.branches) + length(var.environments) > 0
      error_message = "Allow at least one branch or GitHub environment, otherwise no workflow can use this role."
    }
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "workflow-permissions"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]

  tags = local.tags
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:*"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${local.name}-github-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
  tags               = local.tags
}

data "aws_iam_policy_document" "github_deploy" {
  statement {
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeInstanceRefreshes",
      "autoscaling:StartInstanceRefresh",
      "ec2:DescribeInstances",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeLaunchTemplateVersions",
      "elasticloadbalancing:DescribeTargetHealth"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "github_deploy" {
  name   = "${local.name}-github-deploy-policy"
  policy = data.aws_iam_policy_document.github_deploy.json
  tags   = local.tags
}

resource "aws_iam_role_policy_attachment" "github_deploy" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = aws_iam_policy.github_deploy.arn
}

output "github_deploy_role_arn" {
  description = "GitHub Actions OIDC deploy role ARN"
  value       = aws_iam_role.github_deploy.arn
}

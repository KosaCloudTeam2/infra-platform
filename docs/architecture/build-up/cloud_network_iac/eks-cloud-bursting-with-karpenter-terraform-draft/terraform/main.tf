locals {
  name_prefix = "eks-burst"
}

# TODO: Karpenter/IRSA 리소스 추가
# - OIDC provider data 조회
# - IAM role/policy for karpenter controller
# - Helm release(karpenter)

resource "aws_iam_role" "lambda_scale_role" {
  name = "${local.name_prefix}-lambda-scale-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_scale_policy" {
  name = "${local.name_prefix}-lambda-scale-policy"
  role = aws_iam_role.lambda_scale_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeNodegroup",
          "eks:UpdateNodegroupConfig"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "scale_nodegroup" {
  function_name = "scale-eks-nodegroup"
  role          = aws_iam_role.lambda_scale_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  filename      = var.scale_lambda_zip_path

  source_code_hash = filebase64sha256(var.scale_lambda_zip_path)

  environment {
    variables = {
      CLUSTER_NAME   = var.cluster_name
      NODEGROUP_NAME = var.nodegroup_name
      AWS_REGION     = var.aws_region
    }
  }
}

resource "aws_scheduler_schedule" "scale_out" {
  name                         = "ticket-scale-out-before-event"
  schedule_expression          = var.scale_out_schedule
  schedule_expression_timezone = "Asia/Seoul"
  flexible_time_window {
    mode = "OFF"
  }
  target {
    arn      = aws_lambda_function.scale_nodegroup.arn
    role_arn = aws_iam_role.lambda_scale_role.arn
    input = jsonencode({
      desired = 6
      min     = 3
      max     = 10
    })
  }
}

resource "aws_scheduler_schedule" "scale_in" {
  name                         = "ticket-scale-in-after-event"
  schedule_expression          = var.scale_in_schedule
  schedule_expression_timezone = "Asia/Seoul"
  flexible_time_window {
    mode = "OFF"
  }
  target {
    arn      = aws_lambda_function.scale_nodegroup.arn
    role_arn = aws_iam_role.lambda_scale_role.arn
    input = jsonencode({
      desired = 2
      min     = 1
      max     = 4
    })
  }
}

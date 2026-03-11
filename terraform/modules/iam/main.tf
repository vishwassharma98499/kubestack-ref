# ──────────────────────────────────────────────
# IAM Module
# Creates IRSA (IAM Roles for Service Accounts) roles
# for Kubernetes workloads that need AWS API access:
# application pods, ALB controller, external-dns, ArgoCD.
# ──────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  common_tags = merge(var.tags, {
    Module    = "iam"
    ManagedBy = "terraform"
  })
}

# ──────────────────────────────────────────────
# Helper: IRSA trust policy generator
# ──────────────────────────────────────────────
data "aws_iam_policy_document" "irsa_trust" {
  for_each = var.service_accounts

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# ──────────────────────────────────────────────
# IRSA Role: Application Pods
# Grants S3 and SQS access for the sample-api workload.
# ──────────────────────────────────────────────
resource "aws_iam_role" "app" {
  name               = "${var.project}-${var.environment}-app-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust["app"].json

  tags = merge(local.common_tags, {
    Name           = "${var.project}-${var.environment}-app-irsa"
    ServiceAccount = "sample-api"
  })
}

resource "aws_iam_role_policy" "app" {
  name = "${var.project}-${var.environment}-app-policy"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          var.assets_bucket_arn,
          "${var.assets_bucket_arn}/*"
        ]
      }
    ]
  })
}

# ──────────────────────────────────────────────
# IRSA Role: AWS Load Balancer Controller
# ──────────────────────────────────────────────
resource "aws_iam_role" "alb_controller" {
  name               = "${var.project}-${var.environment}-alb-controller-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust["alb-controller"].json

  tags = merge(local.common_tags, {
    Name           = "${var.project}-${var.environment}-alb-controller-irsa"
    ServiceAccount = "aws-load-balancer-controller"
  })
}

resource "aws_iam_role_policy" "alb_controller" {
  name = "${var.project}-${var.environment}-alb-controller-policy"
  role = aws_iam_role.alb_controller.id

  # Full ALB controller policy — covers ALB/NLB/TargetGroup management
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "iam:ListServerCertificates",
          "iam:GetServerCertificate",
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:DeleteSecurityGroup",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:SetWebACL",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule"
        ]
        Resource = "*"
      }
    ]
  })
}

# ──────────────────────────────────────────────
# IRSA Role: ExternalDNS
# ──────────────────────────────────────────────
resource "aws_iam_role" "external_dns" {
  name               = "${var.project}-${var.environment}-external-dns-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust["external-dns"].json

  tags = merge(local.common_tags, {
    Name           = "${var.project}-${var.environment}-external-dns-irsa"
    ServiceAccount = "external-dns"
  })
}

resource "aws_iam_role_policy" "external_dns" {
  name = "${var.project}-${var.environment}-external-dns-policy"
  role = aws_iam_role.external_dns.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = ["arn:aws:route53:::hostedzone/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# ──────────────────────────────────────────────
# IRSA Role: Cert Manager (for DNS-01 challenge)
# ──────────────────────────────────────────────
resource "aws_iam_role" "cert_manager" {
  name               = "${var.project}-${var.environment}-cert-manager-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust["cert-manager"].json

  tags = merge(local.common_tags, {
    Name           = "${var.project}-${var.environment}-cert-manager-irsa"
    ServiceAccount = "cert-manager"
  })
}

resource "aws_iam_role_policy" "cert_manager" {
  name = "${var.project}-${var.environment}-cert-manager-policy"
  role = aws_iam_role.cert_manager.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:GetChange"
        ]
        Resource = ["arn:aws:route53:::change/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        Resource = ["arn:aws:route53:::hostedzone/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZonesByName"]
        Resource = ["*"]
      }
    ]
  })
}

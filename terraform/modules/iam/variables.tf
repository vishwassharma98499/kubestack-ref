variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider (without https://)"
  type        = string
}

variable "assets_bucket_arn" {
  description = "ARN of the application assets S3 bucket"
  type        = string
}

variable "service_accounts" {
  description = "Map of service account configurations for IRSA"
  type = map(object({
    namespace            = string
    service_account_name = string
  }))
  default = {
    "app" = {
      namespace            = "app"
      service_account_name = "sample-api"
    }
    "alb-controller" = {
      namespace            = "ingress"
      service_account_name = "aws-load-balancer-controller"
    }
    "external-dns" = {
      namespace            = "ingress"
      service_account_name = "external-dns"
    }
    "cert-manager" = {
      namespace            = "cert-manager"
      service_account_name = "cert-manager"
    }
  }
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

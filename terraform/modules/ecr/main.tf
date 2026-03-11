# ──────────────────────────────────────────────
# ECR Module
# Creates ECR repositories with lifecycle policies,
# image scanning, and immutable tags for production.
# ──────────────────────────────────────────────

locals {
  common_tags = merge(var.tags, {
    Module    = "ecr"
    ManagedBy = "terraform"
  })
}

resource "aws_ecr_repository" "repos" {
  for_each = toset(var.repository_names)

  name                 = "${var.project}/${each.value}"
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${each.value}"
  })
}

# Lifecycle policy: keep last N tagged images, expire untagged after 14 days
resource "aws_ecr_lifecycle_policy" "repos" {
  for_each = toset(var.repository_names)

  repository = aws_ecr_repository.repos[each.value].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep only the last ${var.max_image_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = var.max_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

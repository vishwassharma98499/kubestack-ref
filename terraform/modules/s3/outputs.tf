output "assets_bucket_id" {
  description = "ID of the application assets bucket"
  value       = aws_s3_bucket.assets.id
}

output "assets_bucket_arn" {
  description = "ARN of the application assets bucket"
  value       = aws_s3_bucket.assets.arn
}

output "state_bucket_id" {
  description = "ID of the Terraform state bucket"
  value       = var.create_state_bucket ? aws_s3_bucket.terraform_state[0].id : null
}

output "state_bucket_arn" {
  description = "ARN of the Terraform state bucket"
  value       = var.create_state_bucket ? aws_s3_bucket.terraform_state[0].arn : null
}

output "dynamodb_lock_table_name" {
  description = "Name of the DynamoDB lock table"
  value       = var.create_state_bucket ? aws_dynamodb_table.terraform_lock[0].name : null
}

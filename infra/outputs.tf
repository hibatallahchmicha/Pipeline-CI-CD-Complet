output "repository_url" {
  description = "URL du repository ECR (à utiliser dans buildspec.yml et les Task Definitions)"
  value       = aws_ecr_repository.app.repository_url
}

output "repository_arn" {
  description = "ARN du repository ECR (pour restreindre la policy IAM de CodeBuild)"
  value       = aws_ecr_repository.app.arn
}
output "repository_url" {
  description = "URL du repository ECR (à utiliser dans buildspec.yml et les Task Definitions)"
  value       = aws_ecr_repository.demo_api.repository_url
}

output "repository_arn" {
  value = aws_ecr_repository.demo_api.arn
}

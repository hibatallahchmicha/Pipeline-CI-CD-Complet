output "repository_url" {
  description = "URL du repository ECR (à utiliser dans buildspec.yml et les Task Definitions)"
  value       = aws_ecr_repository.app.repository_url
}

output "repository_arn" {
  description = "ARN du repository ECR (pour restreindre la policy IAM de CodeBuild)"
  value       = aws_ecr_repository.app.arn
}
# --- Réseau (US 3.1) ---

output "vpc_id" {
  description = "Identifiant du VPC créé"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Identifiants des sous-réseaux publics (utilisés par l'ALB et le service ECS)"
  value       = aws_subnet.public[*].id
}

# --- Load Balancer (US 3.1 / US 3.2) ---

output "alb_dns_name" {
  description = "Nom DNS public de l'ALB — l'URL à ouvrir pour tester l'application"
  value       = aws_lb.main.dns_name
}

output "alb_url" {
  description = "URL complète de l'application déployée"
  value       = "http://${aws_lb.main.dns_name}"
}

output "target_group_arn" {
  description = "ARN du Target Group auquel le Service ECS s'enregistre"
  value       = aws_lb_target_group.app.arn
}

# --- ECS (US 3.2) ---

output "ecs_cluster_name" {
  description = "Nom du cluster ECS (utilisé par l'étape Deploy de CodePipeline)"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Nom du service ECS (utilisé par l'étape Deploy de CodePipeline)"
  value       = aws_ecs_service.app.name
}

output "ecs_container_name" {
  description = "Nom du conteneur — à reprendre à l'identique dans imagedefinitions.json"
  value       = var.container_name
}

output "cloudwatch_log_group" {
  description = "Groupe de logs à consulter en cas d'échec de démarrage d'une tâche"
  value       = aws_cloudwatch_log_group.app.name
}

# --- Build (Sprint 2) ---

output "codebuild_project_name" {
  description = "Nom du projet CodeBuild (étape Build de CodePipeline au Sprint 4)"
  value       = aws_codebuild_project.app.name
}

output "codebuild_role_arn" {
  description = "ARN du rôle IAM de CodeBuild"
  value       = aws_iam_role.codebuild.arn
}

# --- Pipeline et notifications (Sprint 4) ---

output "codepipeline_name" {
  description = "Nom du pipeline CI/CD"
  value       = aws_codepipeline.main.name
}

output "codestar_connection_arn" {
  description = "ARN de la connexion GitHub — à autoriser MANUELLEMENT dans la console"
  value       = aws_codestarconnections_connection.github.arn
}

output "codestar_connection_status" {
  description = "PENDING tant que la connexion GitHub n'est pas autorisee dans la console"
  value       = aws_codestarconnections_connection.github.connection_status
}

output "sns_topic_arn" {
  description = "ARN du topic SNS des notifications de pipeline"
  value       = aws_sns_topic.pipeline.arn
}

output "artifacts_bucket" {
  description = "Bucket S3 de transit des artefacts entre etapes"
  value       = aws_s3_bucket.artifacts.bucket
}

variable "aws_region" {
  description = "Région AWS où déployer les ressources"
  type        = string
  default     = "eu-west-3"
}

variable "ecr_repository_name" {
  description = "Nom du repository ECR"
  type        = string
  default     = "smartovate/demo-api"
}

variable "ecr_image_retention_count" {
  description = "Nombre d'images les plus récentes à conserver dans ECR"
  type        = number
  default     = 10
}

variable "environment" {
  description = "Nom de l'environnement (tag)"
  type        = string
  default     = "dev"
}
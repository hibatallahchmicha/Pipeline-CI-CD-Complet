variable "aws_region" {
  description = "Région AWS où déployer les ressources"
  type        = string
  default     = "eu-west-1"
}

variable "repository_name" {
  description = "Nom du repository ECR"
  type        = string
  default     = "smartovate/demo-api"
}

variable "environment" {
  description = "Nom de l'environnement (tag)"
  type        = string
  default     = "dev"
}

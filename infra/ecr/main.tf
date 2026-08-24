#Terraform va créer un repository Amazon ECR.

#ECR est le registre où tu vas stocker les images Docker.
resource "aws_ecr_repository" "demo_api" {
  name                 = var.repository_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project     = "smartovate-cicd-pipeline"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# US 1.2 : ne conserver que les 10 dernières images pour optimiser les coûts
resource "aws_ecr_lifecycle_policy" "demo_api_lifecycle" {
  repository = aws_ecr_repository.demo_api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Conserver uniquement les 10 dernières images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

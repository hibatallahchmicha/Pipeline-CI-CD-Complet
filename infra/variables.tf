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
variable "aws_profile" {
  description = "Profil AWS CLI utilisé par Terraform (voir ~/.aws/credentials)"
  type        = string
  default     = "smartovate"
}

variable "project_name" {
  description = "Préfixe utilisé pour nommer toutes les ressources"
  type        = string
  default     = "smartovate-cicd"
}

# --- Réseau (Sprint 3 / US 3.1) ---

variable "vpc_cidr" {
  description = "Plage d'adresses IP privées du VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = <<-EOT
    CIDR des sous-réseaux publics. Il en faut au minimum 2, dans 2 zones de
    disponibilité différentes : c'est une exigence de l'Application Load Balancer
    et la base de la haute disponibilité demandée dans l'US 3.1.
  EOT
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

# --- Application (Sprint 3 / US 3.2) ---

variable "container_port" {
  description = "Port exposé par le conteneur Flask (voir app/Dockerfile)"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Route interrogée par le Health Check du Target Group (voir app/app.py)"
  type        = string
  default     = "/health"
}

# --- Maîtrise des coûts ---

variable "desired_count" {
  description = <<-EOT
    Nombre de tâches ECS maintenues en exécution.
    1 pendant le développement (moitié moins cher), 2 pour la démonstration
    finale et les captures d'écran, comme l'exige l'US 3.2.
    Surcharge ponctuelle : terraform apply -var="desired_count=2"
  EOT
  type        = number
  default     = 1
}

# --- Tâches ECS (Sprint 3 / US 3.2) ---

variable "task_cpu" {
  description = <<-EOT
    Unités de CPU allouées à la tâche. 256 = 0,25 vCPU, la valeur exigée par
    l'US 3.2 et le minimum facturable Fargate.
    Fargate n'accepte que des couples CPU/mémoire prédéfinis : 256 impose une
    mémoire comprise entre 512 et 2048 Mo.
  EOT
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Mémoire en Mo allouée à la tâche (512 Mo, conformément à l'US 3.2)"
  type        = number
  default     = 512
}

variable "image_tag" {
  description = <<-EOT
    Tag de l'image ECR déployée par la Task Definition.
    "bootstrap" est l'image poussée à la main pour valider le Sprint 3 ; à partir
    du Sprint 4, CodePipeline déploiera des images taguées avec le SHA du commit.
  EOT
  type        = string
  default     = "bootstrap"
}

variable "log_retention_days" {
  description = "Durée de conservation des logs applicatifs dans CloudWatch (5 Go/mois gratuits)"
  type        = number
  default     = 7
}

# --- Build (Sprint 2 / US 2.1, US 2.2) ---

variable "container_name" {
  description = <<-EOT
    Nom du conteneur dans la Task Definition.
    Cette valeur DOIT être identique dans trois endroits :
      1. container_definitions de la Task Definition (ecs.tf)
      2. le bloc load_balancer du Service ECS (ecs.tf)
      3. le champ "name" de imagedefinitions.json (buildspec.yml)
    Toute divergence fait échouer l'étape Deploy de CodePipeline au Sprint 4.
  EOT
  type        = string
  default     = "demo-api"
}

variable "github_repository_url" {
  description = <<-EOT
    URL HTTPS du dépôt GitHub cloné par CodeBuild (dépôt public : aucun jeton requis).

    On pointe sur le FORK et non sur le dépôt d'origine : le compte utilisé pour
    le développement n'a pas les droits d'écriture sur SihamBouzagrar/... Le
    travail est poussé sur le fork, puis réintégré en amont par pull request.
    Le dépôt d'origine reste accessible via le remote git `upstream`.
  EOT
  type        = string
  default     = "https://github.com/hibatallahchmicha/Pipeline-CI-CD-Complet.git"
}

variable "codebuild_compute_type" {
  description = "Taille de la machine de build. BUILD_GENERAL1_SMALL = 100 min/mois gratuites."
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
}

# --- Pipeline et notifications (Sprint 4 / US 4.1, US 4.2) ---

variable "github_owner" {
  description = "Propriétaire du dépôt GitHub surveillé par CodePipeline"
  type        = string
  default     = "hibatallahchmicha"
}

variable "github_repository" {
  description = "Nom du dépôt GitHub surveillé par CodePipeline"
  type        = string
  default     = "Pipeline-CI-CD-Complet"
}

variable "github_branch" {
  description = "Branche dont chaque push déclenche le pipeline (critère US 4.1)"
  type        = string
  default     = "main"
}

variable "notification_email" {
  description = <<-EOT
    Adresse qui recevra les notifications SNS d'état du pipeline (US 4.2).

    À définir dans `infra/terraform.tfvars`, fichier ignoré par git : l'adresse
    n'est donc pas publiée dans le dépôt public. Exemple de contenu :
        notification_email = "prenom.nom@example.com"

    AWS envoie un mail de confirmation : tant que le lien n'est pas cliqué,
    l'abonnement reste en état "PendingConfirmation" et aucune alerte n'arrive.
  EOT
  type        = string
}

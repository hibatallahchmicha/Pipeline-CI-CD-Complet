terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # Le state est stocké dans S3 (et non en local) pour être partageable et
  # versionné. `use_lockfile` active le verrou natif S3 : deux `apply`
  # simultanés ne peuvent pas corrompre le state.
  # Note : un bloc backend n'accepte pas de variables, tout est en dur.
  backend "s3" {
    bucket       = "smartovate-tfstate-984675940976"
    key          = "cicd/terraform.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true
    profile      = "smartovate"
  }
}

provider "aws" {
  region = var.aws_region

  # Le poste de travail a deux profils AWS configurés (`default` appartient à un
  # autre projet et n'a pas les droits ECR/ECS). On force explicitement le bon
  # profil pour éviter des erreurs AccessDenied difficiles à diagnostiquer.
  profile = var.aws_profile

  # --- Robustesse réseau ---
  # La connexion du poste coupe régulièrement les connexions TLS en cours de
  # lecture de réponse (« wsarecv: An existing connection was forcibly closed »).
  # Symptôme caractéristique : une erreur Terraform accompagnée de
  # `StatusCode: 200` — la ressource EST créée côté AWS, mais la réponse n'est
  # jamais reçue, donc jamais enregistrée dans le state (ressource orpheline).
  # On augmente fortement le nombre de tentatives du SDK AWS.
  max_retries = 25

  default_tags {
    tags = {
      Project     = "smartovate-cicd"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}
# =============================================================================
# US 2.1 / US 2.2 — Projet AWS CodeBuild
# =============================================================================
# CodeBuild est un service de build à la demande : aucune machine à maintenir.
# À chaque exécution, AWS démarre un conteneur neuf, y clone le dépôt, exécute
# `buildspec.yml`, puis détruit la machine. Facturation à la minute de build,
# avec 100 minutes/mois gratuites sur BUILD_GENERAL1_SMALL.
# =============================================================================

# -----------------------------------------------------------------------------
# Groupe de logs dédié au build
# -----------------------------------------------------------------------------
# Sans logs, un build en échec est indiagnosticable. C'est ici que l'on lit la
# sortie de pytest et les éventuelles erreurs d'authentification ECR.
resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${var.project_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-codebuild-logs"
  }
}

# =============================================================================
# Rôle IAM de CodeBuild
# =============================================================================
# C'est le point de défaillance n°1 du Sprint 2 (« Bug 2 » du cahier des
# charges : AccessDeniedException lors du push vers ECR).
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${var.project_name}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json

  tags = {
    Name = "${var.project_name}-codebuild-role"
  }
}

# -----------------------------------------------------------------------------
# Permissions : le strict nécessaire, plutôt que la policy gérée
# -----------------------------------------------------------------------------
# Le cahier des charges suggère `AmazonEC2ContainerRegistryPowerUser`, qui
# donne accès à TOUS les repositories du compte. On écrit ici une politique sur
# mesure, restreinte au seul repository du projet : c'est le principe de
# moindre privilège, à valoriser dans la documentation technique.
data "aws_iam_policy_document" "codebuild" {

  # --- Logs ---
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      aws_cloudwatch_log_group.codebuild.arn,
      "${aws_cloudwatch_log_group.codebuild.arn}:*",
    ]
  }

  # --- Jeton d'authentification ECR ---
  # ATTENTION : `ecr:GetAuthorizationToken` est une action de niveau COMPTE.
  # Elle ne peut pas être restreinte à un repository et exige `resources = ["*"]`.
  # L'oublier produit exactement l'erreur décrite dans le « Bug 2 ».
  statement {
    sid       = "ECRGetAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # --- Push de l'image, limité à NOTRE repository ---
  statement {
    sid    = "ECRPushToProjectRepository"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability", # la couche existe-t-elle déjà ?
      "ecr:InitiateLayerUpload",         # début d'envoi d'une couche
      "ecr:UploadLayerPart",             # envoi par morceaux
      "ecr:CompleteLayerUpload",         # fin d'envoi
      "ecr:PutImage",                    # enregistrement du manifeste + tag
      "ecr:BatchGetImage",               # lecture (cache de couches)
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.app.arn]
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name   = "${var.project_name}-codebuild-policy"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild.json
}

# =============================================================================
# Le projet CodeBuild
# =============================================================================
resource "aws_codebuild_project" "app" {
  name         = "${var.project_name}-build"
  description  = "Tests unitaires, construction et poussee de l'image Docker vers ECR"
  service_role = aws_iam_role.codebuild.arn

  # Durée maximale avant interruption forcée (garde-fou anti-facturation).
  build_timeout = 20

  environment {
    compute_type = var.codebuild_compute_type
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"

    # ⚠️ INDISPENSABLE : sans ce mode, aucun démon Docker n'est disponible
    # dans le conteneur de build et `docker build` échoue immédiatement.
    privileged_mode = true

    # Variables consommées par buildspec.yml.
    # AWS_DEFAULT_REGION est fournie automatiquement par CodeBuild.
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "REPOSITORY_URI"
      value = aws_ecr_repository.app.repository_url
    }

    environment_variable {
      name  = "CONTAINER_NAME"
      value = var.container_name
    }
  }

  # ---------------------------------------------------------------------------
  # Source
  # ---------------------------------------------------------------------------
  # Le dépôt étant PUBLIC, CodeBuild le clone sans authentification : ni jeton
  # personnel GitHub, ni CodeStar Connection ne sont nécessaires au Sprint 2.
  #
  # ⚠️ À MODIFIER AU SPRINT 4 : lorsque le projet sera piloté par CodePipeline,
  # c'est le pipeline qui fournira le code source. Remplacer alors par :
  #     source    { type = "CODEPIPELINE" }
  #     artifacts { type = "CODEPIPELINE" }
  # ---------------------------------------------------------------------------
  source {
    type            = "GITHUB"
    location        = var.github_repository_url
    git_clone_depth = 1
    buildspec       = "buildspec.yml"
  }

  source_version = "main"

  # NO_ARTIFACTS : au Sprint 2 le build est déclenché à la main, aucun artefact
  # n'est transmis. imagedefinitions.json reste vérifiable dans les logs.
  artifacts {
    type = "NO_ARTIFACTS"
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild.name
    }
  }

  tags = {
    Name = "${var.project_name}-build"
  }
}

# =============================================================================
# US 4.1 — CodePipeline : Source → Build → Deploy
# =============================================================================
# CodePipeline est le chef d'orchestre. Il ne construit ni ne déploie rien
# lui-même : il enchaîne des actions confiées à d'autres services, et transporte
# des ARTEFACTS de l'une à l'autre via un bucket S3.
#
#   [Source]  connexion GitHub  → zip du code           → S3
#   [Build]   CodeBuild         → imagedefinitions.json → S3
#   [Deploy]  fournisseur ECS   → lit imagedefinitions.json et met à jour
#                                 le service
#
# Le fichier imagedefinitions.json est le seul lien entre Build et Deploy :
# il indique « le conteneur demo-api doit utiliser telle image ECR ».
# =============================================================================

# -----------------------------------------------------------------------------
# Connexion GitHub (AWS CodeConnections, ex-CodeStar Connections)
# -----------------------------------------------------------------------------
# ⚠️ ÉTAPE MANUELLE OBLIGATOIRE — « Bug 3 » du cahier des charges.
# Terraform crée la connexion en état PENDING. Il faut ensuite ouvrir la console
# (Developer Tools → Settings → Connections → Update pending connection) et
# autoriser l'application « AWS Connector for GitHub ». Tant que l'état n'est
# pas AVAILABLE, l'étape Source échoue et le pipeline ne se déclenche pas.
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.project_name}-github"
  provider_type = "GitHub"
}

# -----------------------------------------------------------------------------
# Bucket S3 des artefacts
# -----------------------------------------------------------------------------
# Zone de transit entre les étapes. Le nom d'un bucket S3 est unique au niveau
# MONDIAL : on y adjoint l'ID du compte pour éviter toute collision.
resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project_name}-artifacts-${data.aws_caller_identity.current.account_id}"

  # Autorise la suppression du bucket même s'il contient encore des artefacts :
  # indispensable pour que `terraform destroy` aboutisse.
  force_destroy = true

  tags = {
    Name = "${var.project_name}-artifacts"
  }
}

# Les artefacts contiennent l'intégralité du code source : le bucket ne doit
# jamais être exposé publiquement.
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Purge automatique : les artefacts n'ont aucune valeur passé quelques jours,
# et le stockage S3 est facturé. Règle d'hygiène et de coût.
resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-artefacts"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }
  }
}

# =============================================================================
# Rôle IAM de CodePipeline
# =============================================================================
data "aws_iam_policy_document" "codepipeline_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline" {
  name               = "${var.project_name}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume.json

  tags = {
    Name = "${var.project_name}-codepipeline-role"
  }
}

data "aws_iam_policy_document" "codepipeline" {

  # --- Lecture/écriture des artefacts ---
  statement {
    sid    = "S3Artifacts"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:GetBucketVersioning",
      "s3:GetBucketLocation",
    ]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*",
    ]
  }

  # --- Étape Source : utiliser la connexion GitHub ---
  statement {
    sid       = "UseGitHubConnection"
    effect    = "Allow"
    actions   = ["codestar-connections:UseConnection"]
    resources = [aws_codestarconnections_connection.github.arn]
  }

  # --- Étape Build : déclencher CodeBuild et suivre son exécution ---
  statement {
    sid    = "StartCodeBuild"
    effect = "Allow"
    actions = [
      "codebuild:StartBuild",
      "codebuild:BatchGetBuilds",
    ]
    resources = [aws_codebuild_project.app.arn]
  }

  # --- Étape Deploy : mettre à jour le service ECS ---
  # RegisterTaskDefinition et Describe* ne peuvent pas être restreints à une
  # ressource : l'API ECS ne le permet pas pour ces actions.
  statement {
    sid    = "DeployToECS"
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
      "ecs:TagResource",
    ]
    resources = ["*"]
  }

  # --- PassRole : autoriser CodePipeline à confier le rôle d'exécution ---
  # Sans cela, RegisterTaskDefinition échoue : on ne peut pas « donner » un rôle
  # à une tâche sans y être explicitement autorisé. C'est une protection contre
  # l'élévation de privilèges. La condition restreint l'usage au service ECS.
  statement {
    sid       = "PassExecutionRoleToECS"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ecs_task_execution.arn]

    condition {
      test     = "StringEqualsIfExists"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "codepipeline" {
  name   = "${var.project_name}-codepipeline-policy"
  role   = aws_iam_role.codepipeline.id
  policy = data.aws_iam_policy_document.codepipeline.json
}

# =============================================================================
# Le pipeline
# =============================================================================
resource "aws_codepipeline" "main" {
  name     = "${var.project_name}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  # V1 : l'offre gratuite AWS inclut UN pipeline actif par mois en V1.
  # Les pipelines V2 sont facturés ~1 $/mois + le temps d'exécution des actions.
  # Les fonctionnalités V2 (variables, déclencheurs fins) ne sont pas requises.
  pipeline_type = "V1"

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  # ---------------------------------------------------------------------------
  # 1. Source — récupérer le code à chaque push sur la branche
  # ---------------------------------------------------------------------------
  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = "${var.github_owner}/${var.github_repository}"
        BranchName       = var.github_branch

        # true = AWS crée automatiquement le webhook GitHub qui déclenche le
        # pipeline à chaque push. C'est ce qui satisfait le critère
        # « déclenchement automatique » de l'US 4.1, et la principale cause du
        # « Bug 3 » lorsqu'il est laissé à false.
        DetectChanges = true
      }
    }
  }

  # ---------------------------------------------------------------------------
  # 2. Build — tests, image Docker, push ECR
  # ---------------------------------------------------------------------------
  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"] # contient imagedefinitions.json

      configuration = {
        ProjectName = aws_codebuild_project.app.name
      }
    }
  }

  # ---------------------------------------------------------------------------
  # 3. Deploy — mise à jour du service ECS
  # ---------------------------------------------------------------------------
  # Le fournisseur ECS lit imagedefinitions.json, enregistre une nouvelle
  # révision de Task Definition avec la nouvelle image, puis met à jour le
  # service. ECS enchaîne alors un déploiement progressif : démarrage des
  # nouvelles tâches, attente des Health Checks de l'ALB, arrêt des anciennes.
  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        ClusterName = aws_ecs_cluster.main.name
        ServiceName = aws_ecs_service.app.name
        FileName    = "imagedefinitions.json"
      }
    }
  }

  tags = {
    Name = "${var.project_name}-pipeline"
  }
}

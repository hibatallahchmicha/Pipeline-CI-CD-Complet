# =============================================================================
# US 4.2 — Notifications d'état du pipeline
# =============================================================================
# Chaîne complète d'une notification :
#
#   CodePipeline change d'état (SUCCEEDED / FAILED)
#        │
#        ▼
#   EventBridge  : règle qui filtre les événements qui nous intéressent
#        │
#        ▼
#   SNS Topic    : diffuse le message à tous ses abonnés
#        │
#        ▼
#   Email        : l'abonné reçoit l'alerte
#
# Chaque maillon a son propre contrôle d'accès : un maillon manquant produit un
# silence total, sans message d'erreur. C'est le piège classique de ce montage.
# =============================================================================

# -----------------------------------------------------------------------------
# Le topic SNS
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "pipeline" {
  name         = "${var.project_name}-pipeline-notifications"
  display_name = "Pipeline Smartovate"

  tags = {
    Name = "${var.project_name}-pipeline-notifications"
  }
}

# -----------------------------------------------------------------------------
# L'abonnement email
# -----------------------------------------------------------------------------
# ⚠️ ÉTAPE MANUELLE : AWS envoie immédiatement un mail « AWS Notification -
# Subscription Confirmation ». Tant que le lien n'est pas cliqué, l'abonnement
# reste en « PendingConfirmation » et AUCUNE notification n'est délivrée.
# Terraform ne peut pas confirmer à votre place (c'est précisément le but).
# Penser à vérifier les spams.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.pipeline.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# -----------------------------------------------------------------------------
# Autoriser EventBridge à publier dans le topic
# -----------------------------------------------------------------------------
# Sans cette politique, la règle EventBridge se déclenche correctement mais la
# publication est refusée silencieusement : aucun mail, aucune erreur visible.
data "aws_iam_policy_document" "sns_topic" {
  statement {
    sid       = "AllowEventBridgePublish"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.pipeline.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "pipeline" {
  arn    = aws_sns_topic.pipeline.arn
  policy = data.aws_iam_policy_document.sns_topic.json
}

# -----------------------------------------------------------------------------
# La règle EventBridge
# -----------------------------------------------------------------------------
# EventBridge reçoit en continu les événements de tous les services AWS. Le
# « pattern » ci-dessous sélectionne uniquement les changements d'état de NOTRE
# pipeline, et seulement les issues définitives (succès ou échec) : sans le
# filtre sur `state`, on recevrait aussi STARTED, SUPERSEDED, etc.
resource "aws_cloudwatch_event_rule" "pipeline_state" {
  name        = "${var.project_name}-pipeline-state"
  description = "Capture les fins d'execution du pipeline CI/CD"

  event_pattern = jsonencode({
    source      = ["aws.codepipeline"]
    detail-type = ["CodePipeline Pipeline Execution State Change"]
    detail = {
      pipeline = [aws_codepipeline.main.name]
      state    = ["SUCCEEDED", "FAILED"]
    }
  })

  tags = {
    Name = "${var.project_name}-pipeline-state"
  }
}

# -----------------------------------------------------------------------------
# La cible : le topic SNS, avec un message lisible
# -----------------------------------------------------------------------------
# Par défaut, SNS transmettrait le JSON brut de l'événement — illisible dans un
# mail. `input_transformer` extrait quelques champs et compose une phrase.
resource "aws_cloudwatch_event_target" "sns" {
  rule      = aws_cloudwatch_event_rule.pipeline_state.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.pipeline.arn

  input_transformer {
    input_paths = {
      pipeline = "$.detail.pipeline"
      state    = "$.detail.state"
      region   = "$.region"
      time     = "$.time"
    }

    # <var> est remplacé par la valeur extraite ci-dessus.
    input_template = <<-EOT
      "Pipeline <pipeline> : execution terminee avec le statut <state> (<time>, region <region>). Console : https://<region>.console.aws.amazon.com/codesuite/codepipeline/pipelines/<pipeline>/view"
    EOT
  }
}

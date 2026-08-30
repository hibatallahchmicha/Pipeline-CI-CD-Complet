# =============================================================================
# US 3.2 — Cluster ECS, Task Definition et Service Fargate
# =============================================================================
# Trois notions à ne pas confondre :
#
#   Cluster         : un simple regroupement logique. Ne coûte rien, ne fait
#                     rien tourner par lui-même.
#   Task Definition : la « recette » d'un conteneur — quelle image, combien de
#                     CPU/mémoire, quel port, où envoyer les logs. Immuable :
#                     chaque modification crée une nouvelle révision (:1, :2…).
#   Service         : le « chef d'orchestre ». Il maintient en permanence N
#                     tâches en vie à partir d'une révision donnée, les
#                     enregistre auprès de l'ALB, et les remplace si elles
#                     meurent.
# =============================================================================

# -----------------------------------------------------------------------------
# Groupe de logs CloudWatch
# -----------------------------------------------------------------------------
# Un conteneur Fargate n'a pas de disque persistant : sans ce groupe de logs,
# la sortie de l'application est perdue et tout diagnostic devient impossible.
# C'est le premier endroit où regarder quand une tâche refuse de démarrer
# (« Bug 1 » du cahier des charges).
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-logs"
  }
}

# -----------------------------------------------------------------------------
# Cluster ECS
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  # Container Insights envoie des métriques détaillées à CloudWatch.
  # Désactivé : facturé au-delà de l'offre gratuite, inutile ici.
  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

# =============================================================================
# Rôle d'exécution de la tâche
# =============================================================================
# DISTINCTION IMPORTANTE, souvent source de confusion :
#
#   Task EXECUTION role : utilisé par l'agent ECS, AVANT que le conteneur ne
#                         démarre — pour tirer l'image depuis ECR et créer le
#                         flux de logs. C'est celui défini ici.
#   Task role           : utilisé par le CODE de l'application une fois lancée
#                         (ex. lire un bucket S3). Notre application Flask
#                         n'appelle aucune API AWS : inutile ici.
# -----------------------------------------------------------------------------

# Politique de confiance : désigne QUI a le droit d'endosser ce rôle.
# Ici, uniquement le service ECS Tasks — personne d'autre.
data "aws_iam_policy_document" "ecs_task_execution_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.project_name}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume.json

  tags = {
    Name = "${var.project_name}-ecs-task-execution-role"
  }
}

# Politique gérée par AWS : contient exactement les droits ECR + CloudWatch Logs
# nécessaires. On la réutilise plutôt que de réécrire une politique maison.
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================================================================
# Task Definition
# =============================================================================
resource "aws_ecs_task_definition" "app" {
  family = "${var.project_name}-task"

  # Fargate = pas de serveur à gérer. AWS fournit la capacité de calcul.
  requires_compatibilities = ["FARGATE"]

  # `awsvpc` est obligatoire avec Fargate : chaque tâche obtient sa propre
  # interface réseau et sa propre IP dans le VPC. C'est aussi la raison pour
  # laquelle le Target Group est en `target_type = "ip"`.
  network_mode = "awsvpc"

  cpu    = var.task_cpu
  memory = var.task_memory

  execution_role_arn = aws_iam_role.ecs_task_execution.arn

  # La définition des conteneurs est du JSON. `jsonencode` permet de l'écrire
  # en syntaxe Terraform, plus lisible et vérifiée à la compilation.
  container_definitions = jsonencode([
    {
      # ⚠️ Nom repris à l'identique dans imagedefinitions.json (Sprint 4).
      name      = var.container_name
      image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
      essential = true # si ce conteneur s'arrête, la tâche entière est arrêtée

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      # Redirige stdout/stderr du conteneur vers CloudWatch Logs.
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      environment = [
        {
          name  = "APP_VERSION"
          value = var.image_tag
        }
      ]
    }
  ])

  tags = {
    Name = "${var.project_name}-task"
  }
}

# =============================================================================
# Service ECS
# =============================================================================
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.public[*].id
    security_groups = [aws_security_group.ecs_tasks.id]

    # Indispensable ici : sans IP publique, la tâche placée dans un
    # sous-réseau public ne peut pas joindre ECR, et le démarrage échoue sur
    # « unable to pull image ». Les alternatives seraient un NAT Gateway
    # (~35 $/mois) ou des VPC Endpoints. Voir le commentaire d'architecture
    # dans network.tf.
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.container_name # doit correspondre au nom ci-dessus
    container_port   = var.container_port
  }

  # « Bug 1 » du cahier des charges : période pendant laquelle les échecs de
  # Health Check sont ignorés, le temps que Flask/gunicorn démarre. Sans ce
  # délai, l'ALB peut déclarer la cible malsaine avant même que l'application
  # ne soit prête, et ECS tue la tâche en boucle.
  health_check_grace_period_seconds = 60

  # Stratégie de déploiement progressif : on autorise jusqu'à 200 % de tâches
  # pendant un déploiement (les nouvelles démarrent avant l'arrêt des
  # anciennes) et jamais moins de 100 % de disponibilité.
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  # Le service ne peut pas s'enregistrer auprès d'un Target Group qui n'est
  # rattaché à aucun Listener. Sans cette dépendance explicite, Terraform peut
  # créer le service trop tôt et échouer.
  depends_on = [aws_lb_listener.http]

  # -------------------------------------------------------------------------
  # À ACTIVER AU SPRINT 4, une fois CodePipeline en place
  # -------------------------------------------------------------------------
  # À partir du moment où le pipeline déploie, c'est LUI qui décide quelle
  # révision de Task Definition tourne. Sans ce bloc, chaque `terraform plan`
  # voudra revenir à la révision qu'il connaît et annulerait le déploiement.
  #
  # Répartition des responsabilités :
  #   Terraform      → la FORME de l'infrastructure
  #   CodePipeline   → la VERSION de l'image qui tourne
  #
  # lifecycle {
  #   ignore_changes = [task_definition, desired_count]
  # }
  # -------------------------------------------------------------------------

  tags = {
    Name = "${var.project_name}-service"
  }
}

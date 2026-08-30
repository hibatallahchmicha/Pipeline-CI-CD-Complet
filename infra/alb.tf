# =============================================================================
# US 3.1 — Application Load Balancer, Target Group et Listener
# =============================================================================
# Chaîne de traitement d'une requête utilisateur :
#
#   Navigateur → DNS de l'ALB → Listener (port 80) → Target Group → Tâche ECS
#
#   - ALB          : le répartiteur de charge public, point d'entrée unique
#   - Listener     : « sur quel port j'écoute, et où j'envoie le trafic »
#   - Target Group : le groupe de destinations + la définition du Health Check
# =============================================================================

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false # false = accessible depuis Internet
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]

  # L'ALB EXIGE au moins 2 sous-réseaux dans 2 AZ différentes.
  # `[*]` extrait la liste des id de tous les subnets créés par `count`.
  subnets = aws_subnet.public[*].id

  # À laisser à false en dev pour pouvoir détruire l'environnement librement.
  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# -----------------------------------------------------------------------------
# Target Group : les destinations et leur surveillance
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg"
  port     = var.container_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # POINT CRITIQUE : "ip" et non "instance".
  # Fargate utilise le mode réseau `awsvpc` : chaque tâche reçoit sa propre
  # interface réseau et sa propre IP privée. Il n'y a aucune instance EC2 à
  # enregistrer. Avec `target_type = "instance"`, la création du service ECS
  # échoue.
  target_type = "ip"

  # --- Health Check (cf. « Bug 1 » du cahier des charges) ---
  # L'ALB interroge cette route en boucle. Une cible qui ne répond pas 200
  # est retirée de la rotation, et pendant un déploiement cela provoque
  # l'annulation (rollback) de la nouvelle version.
  health_check {
    enabled             = true
    path                = var.health_check_path # /health, exposé par app.py
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30 # une vérification toutes les 30 s
    timeout             = 5  # au-delà de 5 s sans réponse = échec
    healthy_threshold   = 2  # 2 succès consécutifs → cible saine
    unhealthy_threshold = 3  # 3 échecs consécutifs → cible retirée
  }

  # Délai laissé aux connexions en cours avant de couper une cible retirée
  # du groupe. 30 s (au lieu de 300 par défaut) accélère les déploiements.
  deregistration_delay = 30

  tags = {
    Name = "${var.project_name}-tg"
  }

  # Le Target Group est référencé par le Service ECS. Pour pouvoir le
  # remplacer sans erreur de dépendance, on crée le nouveau avant de
  # détruire l'ancien.
  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Listener : port 80 → Target Group
# -----------------------------------------------------------------------------
# Le cahier des charges demande explicitement un listener sur le port 80.
# En production on ajouterait un listener 443 (HTTPS) avec un certificat ACM
# et une redirection 80 → 443 ; c'est hors périmètre ici.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

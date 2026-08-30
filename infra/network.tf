# =============================================================================
# US 3.1 — Réseau : VPC, sous-réseaux publics, routage et Security Groups
# =============================================================================
# Rappel du modèle réseau AWS, du plus large au plus étroit :
#   Région (eu-west-3)
#     └── VPC                 : un réseau privé isolé, défini par un CIDR
#           └── Subnet        : une tranche du VPC, rattachée à UNE zone de dispo
#                 └── ENI/IP  : ici, l'interface réseau d'une tâche Fargate
# =============================================================================

# Liste dynamiquement les zones de disponibilité utilisables dans la région.
# On évite ainsi de coder en dur "eu-west-3a" / "eu-west-3b" : le code reste
# portable si on change de région.
data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------------------
# Le VPC
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Indispensables pour que les tâches ECS puissent résoudre les noms DNS
  # d'AWS (notamment l'endpoint ECR d'où l'image Docker est téléchargée).
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# -----------------------------------------------------------------------------
# Internet Gateway : la porte de sortie du VPC vers Internet
# -----------------------------------------------------------------------------
# Sans IGW, le VPC est totalement hermétique. C'est l'IGW qui rend possible
# à la fois le trafic entrant (les utilisateurs vers l'ALB) et sortant
# (les tâches Fargate qui vont chercher leur image dans ECR).
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# -----------------------------------------------------------------------------
# Sous-réseaux publics (un par zone de disponibilité)
# -----------------------------------------------------------------------------
# `count` crée autant de subnets qu'il y a d'entrées dans la liste de CIDR.
# Chacun est placé dans une AZ différente grâce à l'index : si une AZ tombe,
# l'ALB continue de servir le trafic depuis l'autre.
#
# CHOIX D'ARCHITECTURE (à justifier dans la doc technique) :
# La pratique de référence place les conteneurs dans des sous-réseaux PRIVÉS
# avec un NAT Gateway pour la sortie Internet. On a retenu des sous-réseaux
# publics + `assign_public_ip = true` car :
#   - Fargate a besoin d'un accès sortant pour tirer l'image depuis ECR ;
#   - un NAT Gateway coûte ~35 $/mois, hors budget d'un projet de stage ;
#   - la sécurité reste assurée par les Security Groups : les conteneurs
#     n'acceptent QUE le trafic venant de l'ALB (voir plus bas).
# Alternative sans NAT et sans IP publique : des VPC Endpoints vers ECR/S3/Logs.
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # Attribue automatiquement une IP publique aux interfaces créées ici.
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${data.aws_availability_zones.available.names[count.index]}"
    Tier = "public"
  }
}

# -----------------------------------------------------------------------------
# Table de routage
# -----------------------------------------------------------------------------
# Un sous-réseau n'est "public" que parce que sa table de routage envoie
# tout le trafic inconnu (0.0.0.0/0) vers l'Internet Gateway. C'est cette
# ligne, et rien d'autre, qui fait la différence public / privé.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-rt-public"
  }
}

# On associe explicitement chaque sous-réseau à cette table de routage.
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# =============================================================================
# Security Groups — le pare-feu, au niveau de chaque interface réseau
# =============================================================================
# Principe clé : on ne raisonne pas en plages d'IP entre nos propres composants,
# mais en RÉFÉRENÇANT un Security Group depuis un autre. On exprime ainsi une
# règle métier ("seul l'ALB parle aux conteneurs") plutôt qu'une règle réseau.
#
# CONTRAINTE AWS : le champ `description` d'un Security Group (et de ses règles)
# n'accepte QUE les caractères  a-zA-Z0-9 . _-:/()#,@[]+=&;{}!$*
# Ni apostrophes ni lettres accentuées : "l'ALB" ou "sécurité" font échouer la
# création avec  InvalidParameterValue: Invalid security group description.
# Les descriptions ci-dessous sont donc volontairement en ASCII sans apostrophe.
# (Cette contrainte ne s'applique pas aux tags ni aux commentaires.)
# -----------------------------------------------------------------------------

# --- SG de l'ALB : exposé à Internet sur le port 80 ---
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Autorise le trafic HTTP entrant depuis Internet vers le load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP depuis Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # L'ALB doit pouvoir initier des connexions vers les conteneurs
  # (trafic applicatif + health checks).
  egress {
    description = "Tout trafic sortant"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

# --- SG des tâches ECS : joignable UNIQUEMENT par l'ALB ---
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Autorise le trafic applicatif uniquement en provenance du load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Trafic applicatif en provenance du load balancer uniquement"
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"

    # C'est ICI que se joue la sécurité : pas de `cidr_blocks`, mais une
    # référence au SG de l'ALB. Même si la tâche possède une IP publique,
    # personne sur Internet ne peut l'atteindre directement sur le port 8080.
    security_groups = [aws_security_group.alb.id]
  }

  # Sortie ouverte : nécessaire pour tirer l'image depuis ECR et pousser
  # les logs vers CloudWatch.
  egress {
    description = "Tout trafic sortant (ECR, CloudWatch Logs)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ecs-tasks-sg"
  }
}

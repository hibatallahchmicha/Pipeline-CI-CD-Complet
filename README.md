# Smartovate — Pipeline CI/CD (Sprint 1)

Ce dépôt couvre l'**Epic 1** du cahier des charges : préparation du dépôt de code et du registre de conteneurs.

## 0. Prérequis (avant l'US 1.1)

Rien n'étant encore en place côté AWS, commence par ceci :

1. **Compte AWS**
   - Crée un compte sur https://aws.amazon.com si tu n'en as pas (ou utilise un compte fourni par ton entreprise/école).
   - Active le MFA sur le compte root, puis ne l'utilise plus au quotidien.

2. **Utilisateur IAM dédié** (ne jamais utiliser le compte root pour travailler)
   - Console AWS → IAM → Users → Create user (ex: `devops-stagiaire`).
   - Attache (temporairement, pour aller vite) la policy `AdministratorAccess`, ou mieux, uniquement :
     `AmazonEC2ContainerRegistryFullAccess`, `AWSCodeBuildAdminAccess`, `AmazonECS_FullAccess`,
     `IAMFullAccess`, `AWSCloudFormationFullAccess` (tu affineras plus tard).
   - Crée une **clé d'accès** (Access key) pour cet utilisateur → tu obtiens un `Access Key ID` et un `Secret Access Key`.

3. **AWS CLI en local**
   ```bash
   # macOS
   brew install awscli

   # Linux
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip && sudo ./aws/install

   aws configure
   # AWS Access Key ID / Secret Access Key : ceux créés à l'étape 2
   # Default region : eu-west-3 (ou la région de ton choix)
   # Default output format : json
   ```
   Vérifie : `aws sts get-caller-identity` doit renvoyer ton compte.

4. **Terraform**
   ```bash
   brew install terraform      # macOS
   # ou télécharge le binaire : https://developer.hashicorp.com/terraform/install
   terraform -version
   ```

5. **Docker Desktop** installé (nécessaire pour tester l'image en local avant le pipeline).

## 1. US 1.1 — Dépôt de code source (GitHub)

1. Sur GitHub, crée un nouveau dépôt **privé** : `smartovate-cicd-pipeline`.
2. En local :
   ```bash
   cd smartovate-pipeline
   git init
   git add .
   git commit -m "Initial commit: app Flask de démo + module Terraform ECR"
   git branch -M main
   git remote add origin https://github.com/<ton-org>/smartovate-cicd-pipeline.git
   git push -u origin main

   # Création de la branche develop (critère d'acceptation US 1.1)
   git checkout -b develop
   git push -u origin develop
   ```
3. Gère les accès de l'équipe : GitHub → Settings → Collaborators and teams (équivalent GitHub de la config IAM demandée dans le cahier des charges, qui visait CodeCommit).
4. ✅ Critères US 1.1 couverts : dépôt créé, branches `main`/`develop`, code de l'appli de démo poussé.

## 2. US 1.2 — Registre de conteneurs (ECR)

Le module Terraform est dans `infra/`. Il crée :
- un repository ECR **privé**,
- le **scan on push** activé,
- une **lifecycle policy** qui ne garde que les 10 dernières images.

```bash
cd infra
terraform init
terraform plan
terraform apply   # tape "yes" pour confirmer
```

Récupère l'URL du repository :
```bash
terraform output repository_url
```

Teste manuellement le push (avant que CodeBuild ne le fasse automatiquement au Sprint 2) :
```bash
cd ../../app
aws ecr get-login-password --region eu-west-3 | docker login --username AWS --password-stdin 984675940976.dkr.ecr.eu-west-3.amazonaws.com

docker build -t demo-api .
# Le repository est en IMMUTABLE : un tag ne peut jamais etre reecrit.
# On utilise donc un tag unique (ici le SHA du commit) et jamais `latest`.
TAG=$(git rev-parse --short HEAD)
docker tag demo-api:latest 984675940976.dkr.ecr.eu-west-3.amazonaws.com/smartovate/demo-api:$TAG
docker push 984675940976.dkr.ecr.eu-west-3.amazonaws.com/smartovate/demo-api:$TAG
```

✅ Critères US 1.2 couverts : repository privé créé, lifecycle policy (10 images), scan on push activé.

## Structure du dépôt

```
smartovate-pipeline/
├── app/                  # Appli Flask de démo
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   └── tests/test_app.py
├── infra/                # Terraform (state distant dans S3)
│   ├── versions.tf       # providers + backend S3
│   ├── variables.tf
│   ├── main.tf           # Epic 1 : ECR
│   ├── network.tf        # Epic 3 : VPC, subnets, security groups
│   ├── alb.tf            # Epic 3 : ALB, target group, listener
│   ├── ecs.tf            # Epic 3 : cluster, task definition, service
│   └── outputs.tf
├── docs/
│   ├── RUNBOOK.md        # procedure pas a pas + captures a realiser
│   └── captures/
└── README.md
```

## Profil AWS

Le poste de travail a plusieurs profils AWS. Terraform utilise explicitement le profil
`smartovate` (variable `aws_profile` et bloc `backend`), il n'y a donc rien a exporter
avant un `terraform apply`. Pour l'AWS CLI en revanche :

```bash
export AWS_PROFILE=smartovate   # PowerShell : $env:AWS_PROFILE = "smartovate"
```

## Suite du projet

La procedure detaillee des Sprints 2 a 4, avec la liste des captures d'ecran a realiser
pour le rapport, se trouve dans [docs/RUNBOOK.md](docs/RUNBOOK.md).

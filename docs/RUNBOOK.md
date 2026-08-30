# Runbook — Sprints 2 à 4

Procédure pas à pas pour terminer le pipeline CI/CD, avec les captures d'écran à
réaliser pour le rapport de stage.

> **Compte AWS** : `984675940976` · **Région** : `eu-west-3` (Paris) · **Profil CLI** : `smartovate`

---

## Conventions de capture

| Règle | Pourquoi |
|---|---|
| Nommer les fichiers `SXX-NN-description.png` (ex. `S3-04-alb-actif.png`) | Les captures restent triées et référençables depuis le rapport |
| Les déposer dans `docs/captures/` | Elles sont versionnées avec le code |
| Toujours inclure le fil d'Ariane AWS et la région en haut à droite | Prouve *où* la ressource a été créée |
| Masquer l'ID de compte si le rapport est diffusé hors entreprise | 984675940976 est une donnée sensible |
| Pour les terminaux : capturer la commande **et** son résultat | Une sortie sans sa commande n'est pas une preuve |

---

## Particularité PowerShell : toujours guillemeter les valeurs d'option

PowerShell 5.1 découpe les arguments non guillemetés contenant un point. La
commande `terraform destroy -target=aws_lb.main` est transmise à Terraform sous
la forme `-target=aws_lb` + `.main`, d'où l'erreur :

```
Error: Invalid target "aws_lb"
Resource specification must include a resource type and name.
```

Vérification du comportement :

```
cmd /c echo -target=aws_lb.main    ->  -target=aws_lb .main    (découpé)
cmd /c echo -target="aws_lb.main"  ->  -target=aws_lb.main     (correct)
```

**Règle :** sous PowerShell, encadrer systématiquement la valeur de guillemets.

```bash
terraform destroy -target="aws_lb.main"
terraform apply   -var="desired_count=2"
terraform plan    -out="tfplan"
```

Attention également à `-target= aws_lb.main` (espace après le `=`) : la valeur
est alors vide et Terraform renvoie `Invalid target ""`.

---

## Maîtrise des coûts

Le compte n'est plus couvert par l'offre gratuite 12 mois (vérifiable dans
**Billing → Free Tier**). Deux ressources seulement sont facturées :

| Ressource | Coût approximatif |
|---|---|
| Application Load Balancer | ~0,027 $/heure |
| Fargate — 2 tâches (0,25 vCPU + 0,5 Go) | ~0,027 $/heure |
| **Total** | **~0,05 $/heure** |

Tout le reste est gratuit : VPC, sous-réseaux, IGW, tables de routage, Security
Groups, cluster ECS, Task Definitions, rôles IAM, CloudWatch Logs (5 Go/mois
toujours gratuits), SNS (1 M requêtes/mois), CodeBuild (100 min/mois).
Le stockage ECR revient à environ 0,02 €/mois pour une image de 150 Mo.

### Règle de travail : construire, capturer, détruire

L'ALB et les tâches ne sont facturés que tant qu'ils existent. En fin de chaque
séance de travail :

```bash
terraform destroy
```

Environ 3 minutes. La séance suivante, `terraform apply` reconstruit une
infrastructure strictement identique en 4 minutes.

> **Argument à valoriser dans le rapport :** cette capacité à détruire et
> reconstruire l'environnement à l'identique en quelques minutes est le bénéfice
> central de l'Infrastructure as Code. Elle est impossible avec une
> infrastructure créée à la main dans la console.

En travaillant ainsi, le coût total des Sprints 3 et 4 reste **inférieur à 3 $**.

### Trois réflexes complémentaires

1. **`desired_count = 1` par défaut** pendant le développement. Passer à 2
   uniquement pour la démonstration et les captures de l'US 3.2 :
   ```bash
   terraform apply -var="desired_count=2"
   ```
2. **Ne jamais détruire ECR.** C'est la ressource la moins chère (~0,02 €/mois)
   et la plus longue à repeupler. Le `terraform destroy` la supprimerait :
   protéger le repository pendant la phase de développement, ou accepter de
   repousser l'image de bootstrap à chaque cycle.
3. **Vérifier avant de fermer le poste** qu'il ne reste rien de facturé :
   ```bash
   terraform state list
   ```
   S'il ne reste que les deux ressources `aws_ecr_*`, le coût horaire est nul.

> Une alerte budgétaire `logiflow-zero-spend` à 1 $ existe déjà sur le compte
> (AWS Budgets, valable pour l'ensemble du compte). Elle sert de filet de
> sécurité en cas d'oubli.

> 📸 **S3-00-budget-alerte.png** — Billing → Budgets, l'alerte configurée.
> *Légende : « Garde-fou budgétaire mis en place avant tout déploiement. »*

---

## Ordre de réalisation retenu

Le cahier des charges numérote les Epics 2 → 3 → 4. On inverse volontairement les
deux premiers :

> **Sprint 3 (infra) → Sprint 2 (build) → Sprint 4 (pipeline)**

**Justification à reprendre dans le rapport :** l'étape de build produit un fichier
`imagedefinitions.json` qui doit nommer un conteneur d'une Task Definition
existante. Construire l'infrastructure cible d'abord évite une dépendance
circulaire. Cette inversion n'a aucun impact sur les critères d'acceptation.

---

# Sprint 3 — Infrastructure cible ECS Fargate

## Étape 3.0 — Vérifications préalables

```bash
aws sts get-caller-identity --profile smartovate
```
Doit renvoyer `arn:aws:iam::984675940976:user/smartovate-cicd-siham`.

> 📸 **S3-01-identite-aws.png** — la commande et sa sortie.
> *Légende : « Vérification du profil AWS utilisé par Terraform. »*

## Étape 3.1 — Réseau et ALB (US 3.1)

Fichiers concernés : `infra/network.tf`, `infra/alb.tf`.

**Ce qui est créé (12 ressources) :** 1 VPC, 2 sous-réseaux publics dans 2 zones de
disponibilité, 1 Internet Gateway, 1 table de routage + 2 associations,
2 Security Groups, 1 ALB, 1 Target Group, 1 Listener HTTP.

```bash
cd infra
terraform plan
```

> 📸 **S3-02-terraform-plan.png** — la fin de la sortie avec la ligne
> `Plan: 12 to add, 0 to change, 0 to destroy.`
> *Légende : « Plan Terraform de l'infrastructure réseau et du load balancer. »*

```bash
terraform apply
```

> ⚠️ **Coût** : à partir d'ici l'ALB est facturé (~0,027 $/heure, au prorata).
> Tout le reste de cette étape est gratuit. Voir la section
> [Maîtrise des coûts](#maîtrise-des-coûts) : `terraform destroy` en fin de séance.

> 📸 **S3-03-terraform-apply.png** — le résumé `Apply complete! 12 added` avec les
> outputs (`alb_dns_name`, `vpc_id`…).

**Vérifications dans la console AWS :**

1. **VPC → Your VPCs** → sélectionner `smartovate-cicd-vpc`
   > 📸 **S3-04-vpc.png** — *Légende : « VPC dédié au projet, CIDR 10.0.0.0/16. »*

2. **VPC → Subnets** → filtrer sur le VPC
   > 📸 **S3-05-subnets.png** — bien montrer la colonne **Availability Zone** avec
   > deux AZ distinctes (`eu-west-3a` et `eu-west-3b`).
   > *Légende : « Deux sous-réseaux publics dans deux zones de disponibilité :
   > base de la haute disponibilité exigée par l'US 3.1. »*

3. **VPC → Security Groups** → ouvrir `smartovate-cicd-ecs-tasks-sg`, onglet
   **Inbound rules**
   > 📸 **S3-06-security-group-ecs.png** — la règle doit afficher comme source le
   > **SG de l'ALB**, pas une plage d'IP.
   > *Légende : « Les conteneurs n'acceptent que le trafic provenant de l'ALB. »*
   >
   > C'est l'une des captures les plus valorisantes du rapport : elle démontre le
   > principe de moindre privilège au niveau réseau.

4. **EC2 → Load Balancers** → `smartovate-cicd-alb`, état **Active**
   > 📸 **S3-07-alb-actif.png** — montrer le **DNS name** et les deux AZ.

5. **EC2 → Target Groups** → `smartovate-cicd-tg`, onglet **Health checks**
   > 📸 **S3-08-target-group-healthcheck.png** — chemin `/health`, protocole HTTP,
   > matcher 200.
   > *Légende : « Configuration du Health Check — cause principale du Bug 1
   > anticipé au cahier des charges. »*

> À ce stade, ouvrir l'URL de l'ALB renvoie une **erreur 503**. C'est normal et
> attendu : aucune cible n'est encore enregistrée.
> 📸 **S3-09-alb-503.png** — *Légende : « 503 avant déploiement : l'ALB répond
> mais n'a aucune cible saine. »* (montre bien l'avant/après)

### Incident rencontré : ressources orphelines (drift)

Après la correction des descriptions, `terraform apply` a échoué avec :

```
Error: creating Security Group (smartovate-cicd-alb-sg):
api error InvalidGroup.Duplicate: The security group 'smartovate-cicd-alb-sg'
already exists for VPC 'vpc-0361f96bf10cf9c41'
```

**Diagnostic.** Les deux Security Groups existaient bien dans AWS, avec les bonnes
règles, mais n'étaient pas enregistrés dans le fichier d'état Terraform. Une
exécution antérieure les avait créés sans que l'état ne soit écrit.

**Point technique à retenir :** `terraform plan` ne rafraîchit que les ressources
**déjà présentes dans l'état**. Une ressource existante dans AWS mais non suivie
est totalement invisible pour lui — d'où un plan annonçant `4 to add` alors que
2 des 4 existaient déjà. L'état Terraform n'est pas un miroir du cloud : c'est la
liste de ce que Terraform croit gérer.

**Cause racine identifiée plus tard.** Le phénomène s'est reproduit trois fois
(2 Security Groups, l'ALB, puis le rôle IAM). L'erreur sur le rôle IAM est celle
qui a permis de l'expliquer :

```
Error: creating IAM Role (...): operation error IAM: CreateRole,
https response error StatusCode: 200, ...
decomposing response: read tcp 192.168.1.134:57665->44.216.198.20:443:
wsarecv: An existing connection was forcibly closed by the remote host.
```

`StatusCode: 200` est déterminant : **la requête a réussi**, AWS a bien créé la
ressource. C'est la lecture du corps de la réponse qui a été interrompue par la
coupure de la connexion TLS. Terraform n'a donc jamais reçu l'identifiant de la
ressource et n'a rien pu écrire dans le state.

Il ne s'agit ni d'un bug Terraform ni d'un problème de droits IAM, mais d'une
**instabilité de la connexion réseau du poste de travail**.

Mesures prises :

1. `max_retries = 25` dans le bloc `provider "aws"` (`versions.tf`) — le SDK AWS
   retente les appels interrompus.
2. Réduire le parallélisme des applies, pour limiter le nombre de connexions
   TLS simultanées, principal facteur déclenchant :
   ```bash
   terraform apply -parallelism=2
   ```
3. Après toute erreur réseau, **vérifier systématiquement** si la ressource
   existe malgré tout avant de relancer :
   ```bash
   terraform state list
   aws iam get-role --role-name <nom> --profile smartovate
   ```

**Correction — `terraform import`** : adopter l'existant dans l'état plutôt que
de le détruire et le recréer.

```bash
terraform import aws_security_group.alb sg-0e0017186ff271c27
terraform import aws_security_group.ecs_tasks sg-000fcb31e7c962814
```

> 📸 **S3-02b-terraform-import.png** — les deux commandes et leur
> `Import successful!`.
> *Légende : « Reprise en gestion de ressources orphelines par terraform import,
> sans interruption ni recréation. »*

Un `terraform plan` doit ensuite annoncer `2 to add, 0 to change, 0 to destroy` :
zéro modification sur les Security Groups confirme que l'existant correspond
exactement au code.

---

## Étape 3.2 — Image de démarrage dans ECR

La Task Definition référence une image qui doit déjà exister. On en pousse une à
la main, une seule fois ; ensuite c'est CodeBuild qui s'en chargera.

```bash
aws ecr get-login-password --region eu-west-3 --profile smartovate \
  | docker login --username AWS --password-stdin 984675940976.dkr.ecr.eu-west-3.amazonaws.com

cd app
docker build -t smartovate/demo-api .
docker tag smartovate/demo-api:latest 984675940976.dkr.ecr.eu-west-3.amazonaws.com/smartovate/demo-api:bootstrap
docker push 984675940976.dkr.ecr.eu-west-3.amazonaws.com/smartovate/demo-api:bootstrap
```

> ⚠️ Le repository est en `IMMUTABLE` : un tag ne peut **jamais** être réécrit.
> Ne pas utiliser `latest`, sinon le second push échouera avec
> `ImageTagAlreadyExistsException`. C'est un choix volontaire qui garantit la
> traçabilité (une image = un commit).

> 📸 **S3-10-docker-push.png** — la sortie du `docker push`.

**ECR → Repositories → smartovate/demo-api → Images**
> 📸 **S3-11-ecr-image.png** — l'image, son tag et le résultat du **scan de
> vulnérabilités**.
> *Légende : « Image stockée dans ECR avec scan on push activé (US 1.2). »*

## Étape 3.3 — Task Definition et Service ECS (US 3.2)

Fichier concerné : `infra/ecs.tf` *(à écrire — voir étape suivante du projet)*.

**Ce qui est créé :** un cluster ECS, un rôle d'exécution IAM, un groupe de logs
CloudWatch, une Task Definition Fargate (256 CPU / 512 Mo) et un Service à
2 tâches rattaché au Target Group.

```bash
terraform apply
```

> 📸 **S3-12-terraform-apply-ecs.png** — le résumé de l'apply.

**Vérifications :**

1. **ECS → Clusters → smartovate-cicd-cluster → Services** → `Running count 2/2`
   > 📸 **S3-13-service-ecs.png** — *Légende : « Service ECS maintenant 2 tâches
   > en exécution (US 3.2). »*

2. **Onglet Tasks** → les deux tâches en `RUNNING`, dans deux AZ différentes
   > 📸 **S3-14-tasks-running.png**

3. **Task Definition** → onglet détail : `0.25 vCPU`, `0.5 GB`, image ECR
   > 📸 **S3-15-task-definition.png** — *Légende : « Ressources dimensionnées
   > conformément au cahier des charges. »*

4. **EC2 → Target Groups → Targets** → 2 cibles **healthy**
   > 📸 **S3-16-targets-healthy.png** — la capture qui prouve que le Health Check
   > passe.

5. **CloudWatch → Log groups → /ecs/smartovate-cicd** → les logs gunicorn
   > 📸 **S3-17-cloudwatch-logs.png** — *Légende : « Logs applicatifs centralisés,
   > premier réflexe de diagnostic en cas d'échec de déploiement. »*

6. **Le test final** : ouvrir `http://<alb_dns_name>` dans le navigateur
   > 📸 **S3-18-application-en-ligne.png** — le JSON `{"message": "Bienvenue sur
   > l'API de démo Smartovate", "version": "..."}` avec l'URL visible.
   > *Légende : « Application accessible via le nom DNS de l'ALB — dernier critère
   > d'acceptation de l'US 3.2. »*
   >
   > 📸 **S3-19-application-health.png** — également `http://<alb_dns_name>/health`.

---

# Sprint 2 — Build automatisé (CodeBuild)

## Étape 2.1 — `buildspec.yml` (US 2.1)

Fichier à créer à la racine du dépôt. Quatre phases :

| Phase | Rôle |
|---|---|
| `install` | Choix du runtime Python, installation des dépendances |
| `pre_build` | Authentification à ECR **puis** exécution de `pytest` |
| `build` | `docker build` et tag avec le SHA du commit |
| `post_build` | `docker push` et génération de `imagedefinitions.json` |

Deux points à expliquer dans le rapport :

- **Les tests sont en `pre_build`**, avant la construction de l'image : un test en
  échec interrompt le build immédiatement, sans consommer de temps de build ni
  polluer ECR.
- **`imagedefinitions.json`** est le contrat entre l'étape Build et l'étape Deploy.
  Il contient `[{"name":"<nom du conteneur>","imageUri":"<image ECR>"}]` et c'est
  la seule information que CodePipeline transmet à ECS.

> 📸 **S2-01-buildspec.png** — le fichier ouvert dans l'éditeur.

## Étape 2.2 — Projet CodeBuild et rôle IAM (US 2.2)

Fichier concerné : `infra/codebuild.tf`.

Paramètres déterminants :
- `privileged_mode = true` — **obligatoire**, sinon aucun démon Docker n'est
  disponible dans le conteneur de build et `docker build` échoue ;
- rôle IAM avec `ecr:GetAuthorizationToken` (sur `*`, c'est une action de niveau
  compte) + les actions d'upload de couches sur le repository + les droits
  CloudWatch Logs. **C'est exactement le « Bug 2 » du cahier des charges.**

```bash
terraform apply
aws codebuild start-build --project-name smartovate-cicd-build --profile smartovate --region eu-west-3
```

> 📸 **S2-02-codebuild-projet.png** — CodeBuild → le projet, avec **Privileged**
> à `Enabled`.

> 📸 **S2-03-codebuild-role-iam.png** — IAM → le rôle → la policy ECR.
> *Légende : « Permissions ECR du rôle CodeBuild — prévention du Bug 2
> (AccessDeniedException au push). »*

> 📸 **S2-04-build-succeeded.png** — l'historique du build en **Succeeded**,
> les 4 phases en vert.

> 📸 **S2-05-build-logs-tests.png** — dans les logs, la sortie `pytest`
> (`2 passed`).
> *Légende : « Exécution automatique des tests unitaires (critère US 2.1). »*

> 📸 **S2-06-ecr-image-sha.png** — ECR, la nouvelle image taguée avec le SHA du
> commit.
> *Légende : « Image tagguée avec le SHA du commit, garantissant la traçabilité
> entre le code et le conteneur déployé (critère US 2.2). »*

---

# Sprint 4 — Pipeline et notifications

## Étape 4.1 — Connexion GitHub

Terraform crée la connexion CodeStar à l'état **`PENDING`**. Il faut
obligatoirement finaliser l'autorisation OAuth **à la main** :

> Console → **Developer Tools → Settings → Connections** → sélectionner la
> connexion → **Update pending connection** → autoriser l'application
> *AWS Connector for GitHub* sur le dépôt.

Tant que l'état n'est pas **`Available`**, le pipeline ne se déclenchera jamais.
C'est le « Bug 3 » du cahier des charges.

> 📸 **S4-01-connexion-pending.png** — l'état `Pending` (l'avant).
> 📸 **S4-02-connexion-available.png** — l'état `Available` (l'après).
> *Légende : « Autorisation manuelle de la connexion GitHub — étape non
> automatisable par l'IaC pour des raisons de sécurité. »*

## Étape 4.2 — Le pipeline (US 4.1)

Fichier concerné : `infra/codepipeline.tf`. Trois étapes : **Source** (GitHub,
branche `main`, `detect_changes = true`) → **Build** (le projet CodeBuild) →
**Deploy** (fournisseur ECS).

> ⚠️ **Piège à documenter** : une fois le pipeline actif, Terraform et
> CodePipeline se disputent la Task Definition — chaque `terraform plan`
> voudra revenir à la révision qu'il connaît. Ajouter dans
> `aws_ecs_service` :
> ```hcl
> lifecycle {
>   ignore_changes = [task_definition, desired_count]
> }
> ```
> Répartition des responsabilités : **Terraform possède la forme de
> l'infrastructure, le pipeline possède la version déployée.**

**Le test de bout en bout** — modifier `APP_VERSION` ou le message dans
`app/app.py`, puis :
```bash
git commit -am "test: déclenchement du pipeline" && git push origin main
```

> 📸 **S4-03-pipeline-vue-globale.png** — les 3 étapes en vert.
> *Légende : « Pipeline CI/CD complet exécuté de bout en bout (critère US 4.1). »*
> **C'est la capture centrale du rapport.**

> 📸 **S4-04-pipeline-source.png** — le détail de l'étape Source montrant le
> commit qui a déclenché l'exécution (prouve le déclenchement automatique).

> 📸 **S4-05-ecs-deploiement.png** — ECS → Service → onglet **Deployments**
> pendant le rolling update : ancienne et nouvelle révision coexistent.
> *Légende : « Déploiement progressif : les nouvelles tâches ne reçoivent du
> trafic qu'une fois déclarées saines par l'ALB — zéro interruption de service. »*

> 📸 **S4-06-application-nouvelle-version.png** — le navigateur affichant la
> nouvelle version. **À mettre côte à côte avec S3-18** dans le rapport : c'est la
> démonstration visuelle que le pipeline fonctionne.

## Étape 4.3 — Notifications (US 4.2)

Fichier concerné : `infra/notifications.tf`. Trois ressources et une policy :
topic SNS + abonnement email + règle EventBridge + policy autorisant
`events.amazonaws.com` à publier sur le topic (sans elle, la règle se déclenche
mais aucun mail ne part).

> ⚠️ AWS envoie un mail de confirmation d'abonnement : **il faut cliquer sur le
> lien**, sinon l'abonnement reste en `PendingConfirmation`.

> 📸 **S4-07-sns-topic.png** — le topic et l'abonnement **Confirmed**.
> 📸 **S4-08-eventbridge-rule.png** — le pattern d'événement
> (`aws.codepipeline`, états `SUCCEEDED` / `FAILED`).
> 📸 **S4-09-email-notification.png** — le mail reçu dans la boîte de réception.
> *Légende : « Notification automatique de l'état du pipeline (US 4.2). »*

---

## Captures bonus (fortement valorisées)

| Capture | Pourquoi c'est intéressant |
|---|---|
| **BONUS-01-echec-provoque.png** | Casser volontairement un test, pousser, montrer le pipeline en **Failed** à l'étape Build + le mail d'alerte. Prouve que les garde-fous fonctionnent réellement. |
| **BONUS-02-ecr-lifecycle.png** | La lifecycle policy ECR (10 images) — critère US 1.2 souvent oublié dans les rapports. |
| **BONUS-03-cout.png** | AWS Cost Explorer / Billing sur la période du projet. Démontre une conscience FinOps. |
| **BONUS-04-terraform-destroy.png** | La destruction propre de l'environnement. Montre la maîtrise du cycle de vie complet de l'IaC. |

---

## Récapitulatif : couverture des critères d'acceptation

| US | Critère | Preuve |
|---|---|---|
| 1.1 | Dépôt + branches `main`/`develop` | Capture GitHub |
| 1.2 | ECR privé, lifecycle 10 images, scan on push | S3-11, BONUS-02 |
| 2.1 | Build exécute les tests unitaires | S2-04, S2-05 |
| 2.2 | Image taguée SHA, poussée vers ECR, rôle IAM | S2-06, S2-03 |
| 3.1 | Cluster, ALB, Target Group, Listener, SG | S3-04 → S3-08 |
| 3.2 | Task Definition, 2 tâches, ALB, accès DNS | S3-13 → S3-18 |
| 4.1 | Pipeline 3 étapes, déclenchement auto, deploy ECS | S4-03, S4-04, S4-05 |
| 4.2 | SNS, EventBridge, réception des notifications | S4-07 → S4-09 |

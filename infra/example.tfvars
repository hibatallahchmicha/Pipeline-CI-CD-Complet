# Modèle de configuration locale.
# Copier vers `terraform.tfvars` (ignoré par git) et renseigner les valeurs.
#
#   cp example.tfvars terraform.tfvars
#
# `terraform.tfvars` est lu automatiquement par Terraform à chaque commande.

# Adresse qui recevra les notifications d'état du pipeline (US 4.2).
# AWS envoie un mail de confirmation : le lien DOIT être cliqué pour que
# l'abonnement passe de "PendingConfirmation" à "Confirmed".
notification_email = "sihambouzagrar@gmail.com"

# Nombre de tâches ECS. 1 en développement, 2 pour la démonstration (US 3.2).
# desired_count = 1

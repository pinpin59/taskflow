#!/usr/bin/env bash
# ============================================================================
# deploy.sh : met un environnement TaskFlow (staging ou prod) à une version donnée.
#
# À lancer depuis le dossier de l'environnement (PROD_DIR ou STAGING_DIR), qui
# contient le fichier compose et le .env :
#     ./deploy.sh <tag>                                    # prod (compose.prod.yaml)
#     COMPOSE_FILE=compose.staging.yaml ./deploy.sh <tag>  # staging
#   <tag> = SHA court (7 caractères) d'une image publiée, ou "latest".
#
# Rollback : relancer avec un tag précédent (voir .previous_tag).
# Le script est idempotent : le relancer avec le même tag ne casse rien.
# ============================================================================
set -euo pipefail

TAG="${1:?Usage: ./deploy.sh <tag>  (ex: ./deploy.sh a1b2c3d)}"
if [[ ! "$TAG" =~ ^([0-9a-f]{7}|latest)$ ]]; then
  echo "Tag invalide : '$TAG' (attendu : SHA court de 7 caractères ou 'latest')" >&2
  exit 1
fi

DEPLOY_DIR="${DEPLOY_DIR:-$(cd "$(dirname "$0")" && pwd)}"
cd "$DEPLOY_DIR"

# docker compose lit lui-même COMPOSE_FILE : pas besoin de -f partout.
export COMPOSE_FILE="${COMPOSE_FILE:-compose.prod.yaml}"
export IMAGE_TAG="$TAG"

[ -f "$COMPOSE_FILE" ] || { echo "Fichier $COMPOSE_FILE absent de $DEPLOY_DIR" >&2; exit 1; }
[ -f .env ] || { echo ".env absent de $DEPLOY_DIR : il se crée à la main (jamais dans Git)" >&2; exit 1; }

echo "==> $COMPOSE_FILE : déploiement de $TAG dans $DEPLOY_DIR"

# Mémorise la version actuelle AVANT de la remplacer : c'est la cible du rollback.
if [ -f .deployed_tag ] && [ "$(cat .deployed_tag)" != "$TAG" ]; then
  cp .deployed_tag .previous_tag
fi

echo "==> Téléchargement des images"
docker compose pull --quiet

# --wait : attend que les healthchecks soient verts (échec si un service reste
# unhealthy). up -d ne recrée que les conteneurs dont l'image ou la config a changé.
echo "==> Mise à jour des services"
docker compose up -d --remove-orphans --wait --wait-timeout 120

# Le proxy (prod seulement) a résolu l'IP du front au démarrage : après un
# redéploiement du front, on le recharge (sans coupure) pour qu'il la redécouvre.
if docker compose config --services | grep -qx proxy; then
  echo "==> Rechargement du proxy"
  docker compose exec -T proxy nginx -t -q
  docker compose exec -T proxy nginx -s reload
fi

echo "$TAG" > .deployed_tag
docker compose ps --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}'

# Images orphelines (« dangling ») seulement : les anciennes versions taguées
# restent en cache, ce qui rend un rollback quasi instantané.
docker image prune -f >/dev/null

echo "==> Déployé : $TAG (précédent : $(cat .previous_tag 2>/dev/null || echo aucun))"

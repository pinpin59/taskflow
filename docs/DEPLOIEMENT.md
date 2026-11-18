# Procédure de déploiement

TaskFlow a trois environnements, sur la même machine dans le lab :

| Environnement | Où | Fichier Compose | Projet Compose | Accès |
|---|---|---|---|---|
| dev | clone du dépôt | `compose.yaml` (build local) | `taskflow` | `http://localhost:8080` |
| staging | `STAGING_DIR` = `~/taskflow-staging` | `compose.staging.yaml` | `taskflow-staging` | `http://localhost:8081` (pas de proxy, pas de TLS) |
| production | `PROD_DIR` = `~/taskflow-prod` | `compose.prod.yaml` | `taskflow-prod` | `https://taskflow.localhost` (proxy Nginx, TLS auto-signé) |

Staging et production exécutent **les mêmes images**, identifiées par le SHA court du commit (`IMAGE_TAG`). Seule la
configuration change, et elle vient du `.env` de chaque dossier (jamais dans Git).

## Ce qui est versionné, ce qui ne l'est pas

| Versionné (copié par le pipeline) | Uniquement dans le dossier de l'environnement |
|---|---|
| `compose.prod.yaml`, `compose.staging.yaml` | `.env` (`chmod 600`, un secret différent par environnement) |
| `deploy/nginx/taskflow.conf` → `nginx/` | `certs/` (prod) |
| `deploy/deploy.sh`, `smoke-test.sh`, `backup.sh`, `gen-cert.sh` | `backups/`, `.deployed_tag`, `.previous_tag` |

## A. Première mise en place (une fois par environnement)

```bash
REPO=~/taskflow
# Production
mkdir -p ~/taskflow-prod/nginx && cd ~/taskflow-prod
cp $REPO/compose.prod.yaml $REPO/deploy/*.sh . && cp $REPO/deploy/nginx/taskflow.conf nginx/
cp $REPO/.env.example .env && chmod 600 .env
PASS=$(openssl rand -hex 24); sed -i "s/changez-moi/$PASS/g" .env   # puis GHCR_OWNER (minuscules), ports
./gen-cert.sh
./deploy.sh <sha-court>

# Staging
mkdir -p ~/taskflow-staging && cd ~/taskflow-staging
cp $REPO/compose.staging.yaml $REPO/deploy/deploy.sh $REPO/deploy/smoke-test.sh .
cp $REPO/.env.example .env && chmod 600 .env
PASS=$(openssl rand -hex 24); sed -i "s/changez-moi/$PASS/g; s/^APP_ENV=.*/APP_ENV=staging/" .env
COMPOSE_FILE=compose.staging.yaml ./deploy.sh <sha-court>
```

Images privées : `docker login ghcr.io` avec un jeton `read:packages` (ou rendre les paquets publics).
Ports 80/443 pris ou Docker rootless : `HTTP_PORT=8082` et `HTTPS_PORT=8443` dans `~/taskflow-prod/.env`.

Vérifier :

```bash
curl -fsS http://localhost:8081/health
curl -fsS --cacert ~/taskflow-prod/certs/taskflow.crt https://localhost:${HTTPS_PORT:-443}/health
curl -sI http://localhost:${HTTP_PORT:-80}/ | grep -i location        # redirection vers https
```

## B. Livraison automatique (`.github/workflows/release.yml`)

Un merge sur `main` :

1. `prepare` calcule le tag (`${GITHUB_SHA::7}`) et le plan ;
2. `images` (matrice api / front) : build → **Trivy** (échec sur une vulnérabilité CRITICAL corrigeable) → push
   `ghcr.io/<owner>/taskflow-<composant>:<sha>` et `:latest` ;
3. `deploy-staging` (runner `[self-hosted, lab]`, environment `staging`) : copie des fichiers, `deploy.sh`,
   smoke test `http://host.docker.internal:8081/health` qui vérifie **la version** ;
4. `deploy-production` (environment `production`, **approbation requise**) : sauvegarde de la base, `deploy.sh`,
   smoke test HTTPS avec vérification du certificat, **rollback automatique** vers `.previous_tag` si le smoke test échoue.

Configuration GitHub nécessaire :

| Élément | Où | Valeur |
|---|---|---|
| Runner | `ressources/lab/runner` | labels `self-hosted,lab` ; `PROD_DIR`, `STAGING_DIR` |
| Environment `staging` | Settings > Environments | aucune protection ; variable `FRONT_PORT` si ≠ 8081 |
| Environment `production` | Settings > Environments | *Required reviewers* ; *Deployment branches* : `main` ; variable `HTTPS_PORT` si ≠ 443 |
| Fork PR workflows | Settings > Actions > General | *Require approval for all outside collaborators* |

Livraison continue ↔ déploiement continu : retirer les *required reviewers* de `production`. Le YAML ne change pas.

## C. Rollback

1. Trouver le tag sain : `cat ~/taskflow-prod/.previous_tag`, un run *Release* vert, ou la liste des versions du paquet.
2. **Actions > Release > Run workflow** : `tag` = SHA court, `environment` = `staging` ou `production`
   (`gh workflow run release.yml -f tag=a1b2c3d -f environment=production`). Build et scan sont sautés ;
   la production demande toujours l'approbation.
3. En urgence, sur la machine : `cd ~/taskflow-prod && ./deploy.sh a1b2c3d`.

Le rollback ne revient que sur le **code**. Si la version fautive a modifié la base, restaurer la sauvegarde prise
juste avant le déploiement (section D). Les migrations doivent être compatibles avec la version N-1 (*expand/contract*).

## D. Sauvegarde et restauration

```bash
cd ~/taskflow-prod && ./backup.sh                                     # backups/taskflow-<date>.sql.gz, 7 jours
gunzip -c backups/taskflow-XXXX.sql.gz | docker compose -f compose.prod.yaml exec -T db psql -U taskflow -d taskflow
```

Une sauvegarde jamais restaurée n'est pas une sauvegarde.

## E. Secrets

- Aucun secret dans Git : hook `pre-commit` gitleaks (`.pre-commit-config.yaml` : `pipx install pre-commit && pre-commit install`).
- Le pipeline n'a besoin d'**aucun** secret créé à la main : `GITHUB_TOKEN` (éphémère, permissions minimales par job)
  suffit pour ghcr.io. Les `.env` ne quittent jamais les dossiers des environnements.
- Secret exposé : **révoquer d'abord**, purger l'historique ensuite (`git filter-repo`), puis prévenir.

## F. Check-list de mise en production

- [ ] `.env` en `-rw-------` dans chaque dossier, mots de passe différents entre staging et prod
- [ ] `GHCR_OWNER` en minuscules
- [ ] `docker compose ps` : tous les services `healthy` ; seul `proxy` publie des ports en prod
- [ ] `/health` renvoie `"status":"ok"` et le SHA attendu, sur les deux environnements
- [ ] HTTP redirige vers HTTPS ; TLS 1.2 minimum
- [ ] Une sauvegarde a été restaurée au moins une fois
- [ ] Le rollback a été testé (`.previous_tag` connu)

## G. Sur un vrai serveur

| Sujet | Lab | Vrai serveur |
|---|---|---|
| Qui déclenche | runner self-hosted sur le poste (pull) | job `ubuntu-latest` qui se connecte en **SSH** (push), ou agent GitOps |
| Accès | socket Docker monté dans le runner | clé SSH dans un secret d'environment, utilisateur `deploy` non-root |
| Certificat | auto-signé (`gen-cert.sh`) | Let's Encrypt (`certbot`), renouvelé automatiquement |
| Staging | même machine que la prod | machine (ou namespace, ou compte cloud) séparée |
| Smoke test | `host.docker.internal` + `--cacert` | URL publique, certificat reconnu |

Esquisse du job SSH : `demos/demo-ssh-serveur/README.md`.

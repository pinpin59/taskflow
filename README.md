# TaskFlow

Un gestionnaire de tâches volontairement simple : c'est le **fil rouge** de la formation DevOps. Le code applicatif est
fourni et testé ; votre travail porte sur tout ce qui l'entoure : intégration continue, livraison, infrastructure,
supervision, sécurité.

| Partie | Technologie | Port |
| --- | --- | --- |
| `front/` | Vite + JavaScript sans framework, servi par **Nginx** dans son image | 5173 en dev (Vite), 80 dans le conteneur |
| `api/` | Node 20 + Express + `pg` | 3000 |
| base | PostgreSQL 16 (table `tasks`, créée au démarrage de l'API) | 5432 |

## Structure

```
taskflow/
├── api/
│   ├── src/                 app.js (routes), server.js (démarrage), config.js, db.js, logger.js
│   │   └── repositories/    memory.js (tests, sans base) et postgres.js (réel)
│   ├── tests/               *.test.js (unitaires), db.int.test.js (intégration, base requise)
│   ├── vitest.config.js     configuration des tests et de la couverture
│   ├── Dockerfile           image de l'API (node:20-alpine, USER node, HEALTHCHECK)
│   └── .env.example         variables d'environnement documentées
├── front/
│   ├── index.html, src/     interface (main.js) et client HTTP (api.js)
│   ├── tests/               tests du client HTTP
│   ├── vite.config.js       serveur de dev (proxy /api → :3000) et tests
│   ├── Dockerfile           build multi-stage : Node compile, Nginx sert
│   └── nginx.conf           sert le site et relaie /api et /health vers l'API
├── compose.yaml             environnement de développement complet (db + api + front)
├── .github/                 modèle de PR, CODEOWNERS, configuration d'actionlint
└── docs/ARCHITECTURE.md     qui tourne où, qui parle à qui
```

## Ce qu'il faut sur votre poste

Git, Node.js 20 ou plus (`node -v`), Docker avec Compose v2 (`docker compose version`). Détails :
`ressources/setup-poste.md` du dépôt de formation.

## Lancer l'application

### Option 1 : tout avec Docker Compose (recommandé)

```bash
docker compose up -d --build     # construit les images api et front, démarre db, api, front
docker compose ps                # les trois services doivent être "healthy" (20 à 30 s)
```

Application : <http://localhost:8080> · santé : <http://localhost:8080/health>
→ `{"status":"ok","db":"up","version":"dev","env":"local"}`.

| Commande | Effet |
| --- | --- |
| `docker compose logs -f api` | suivre les logs de l'API (une ligne JSON par requête) |
| `docker compose exec db psql -U taskflow` | console SQL dans la base |
| `docker compose up -d --build api` | reconstruire et relancer l'API après une modification |
| `docker compose down` | arrêter et supprimer les conteneurs (**les données restent** dans le volume `pgdata`) |
| `docker compose down -v` | idem **et** supprimer le volume : base vide au prochain démarrage |

Seul le front publie un port (8080) : l'API et la base ne sont joignables que sur le réseau privé de Compose.

### Option 2 : en local, avec rechargement à chaud

```bash
# 1. Une base PostgreSQL (seule)
docker run -d --name taskflow-db -p 5432:5432 \
  -e POSTGRES_USER=taskflow -e POSTGRES_PASSWORD=taskflow -e POSTGRES_DB=taskflow \
  docker.io/library/postgres:16-alpine

# 2. L'API (terminal 1)
cd api && npm ci && npm run dev          # http://localhost:3000/health

# 3. Le front (terminal 2)
cd front && npm ci && npm run dev        # http://localhost:5173 (Vite relaie /api et /health vers :3000)
```

Arrêt de la base : `docker rm -f taskflow-db`. Ne lancez pas les deux options en même temps si vous publiez 5432.

## Variables d'environnement de l'API

| Variable | Défaut | Rôle |
| --- | --- | --- |
| `PORT` | `3000` | port d'écoute |
| `DATABASE_URL` | `postgres://taskflow:taskflow@localhost:5432/taskflow` | connexion PostgreSQL |
| `APP_ENV` | `local` | `local`, `staging` ou `production` (affiché par `/health`) |
| `APP_VERSION` | `dev` | version affichée par `/health` (le pipeline y mettra le SHA court du commit) |

Voir `api/.env.example`. **Ne commitez jamais** de fichier `.env` (il est dans `.gitignore`).

## Tests et qualité

Dans `api/` **et** dans `front/` :

| Commande | Rôle |
| --- | --- |
| `npm run lint` | ESLint |
| `npm run format:check` / `npm run format` | vérifier / appliquer le formatage Prettier |
| `npm test` | tests (Vitest) |
| `npm run test:coverage` | tests + couverture : tableau dans la console, résumé dans `coverage/coverage-summary.json` |

Spécifique à l'API : les tests d'**intégration** (`tests/db.int.test.js`) ne tournent que si `DATABASE_URL` est
défini ; sinon ils sont ignorés (*skipped*) :

```bash
cd api
npm test                     # Tests  27 passed | 10 skipped (37)
DATABASE_URL=postgres://taskflow:taskflow@localhost:5432/taskflow npm run test:int   # Tests  10 passed (10)
```

> Les tests d'intégration **vident** la table `tasks` : lancez-les contre une base jetable, jamais contre une base qui
> contient des données utiles.

## Aperçu de l'API

| Méthode et chemin | Rôle | Réponse |
| --- | --- | --- |
| `GET /api/tasks` | liste des tâches | 200 |
| `POST /api/tasks` avec `{ "title": "..." }` | crée une tâche | 201, ou 400 si le titre est vide |
| `PATCH /api/tasks/:id/toggle` | bascule terminée / à faire | 200 ou 404 |
| `DELETE /api/tasks/:id` | supprime une tâche | 204 ou 404 |
| `GET /health` | état de l'API et de la base | 200, ou **503** si la base ne répond pas |

`/health` sert au healthcheck Docker, au smoke test du pipeline et à la supervision.

## Contribuer

- Une branche par sujet, une PR vers `main` (protégée : revue obligatoire, checks requis), fusion en *squash*.
- Titres de PR et messages de commit au format *Conventional Commits* : `feat:`, `fix:`, `ci:`, `build:`, `docs:`,
  `test:`, `chore:`.
- Avant de pousser : `npm run lint && npm run format:check && npm test` dans le(s) dossier(s) modifié(s).

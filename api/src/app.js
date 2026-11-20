// createApp() construit l'application Express SANS la démarrer.
// Grâce à cela, les tests (supertest) l'appellent directement, avec un
// repository en mémoire : pas de port réseau, pas de base de données.
import express from 'express';
import { createRequestLogger, writeLog } from './logger.js';
import { defaultMetrics } from './metrics.js';

const MAX_TITLE_LENGTH = 200;

// Express 4 ne gère pas les erreurs des fonctions async : on les transmet à next().
const asyncHandler = (handler) => (req, res, next) =>
  Promise.resolve(handler(req, res, next)).catch(next);

// "12" -> 12 ; "abc", "-1", "1.5" -> null
function parseId(value) {
  const id = Number(value);
  return Number.isInteger(id) && id > 0 ? id : null;
}

// Renvoie le titre nettoyé, ou null s'il est invalide.
function parseTitle(body) {
  const title = typeof body?.title === 'string' ? body.title.trim() : '';
  const isValid = title.length > 0 && title.length <= MAX_TITLE_LENGTH;
  return isValid ? title : null;
}

function createTaskRoutes(repository, { tasksCreatedTotal } = {}) {
  const router = express.Router();

  router.get(
    '/',
    asyncHandler(async (_req, res) => {
      res.json(await repository.list());
    }),
  );

  router.post(
    '/',
    asyncHandler(async (req, res) => {
      const title = parseTitle(req.body);
      if (!title) {
        return res.status(400).json({
          error: `Le titre est obligatoire (1 à ${MAX_TITLE_LENGTH} caractères)`,
        });
      }
      const task = await repository.create(title);
      tasksCreatedTotal?.inc();
      return res.status(201).json(task);
    }),
  );

  router.patch(
    '/:id/toggle',
    asyncHandler(async (req, res) => {
      const id = parseId(req.params.id);
      if (!id) return res.status(400).json({ error: 'Identifiant invalide' });

      const task = await repository.toggle(id);
      if (!task) return res.status(404).json({ error: 'Tâche introuvable' });
      return res.json(task);
    }),
  );

  router.delete(
    '/:id',
    asyncHandler(async (req, res) => {
      const id = parseId(req.params.id);
      if (!id) return res.status(400).json({ error: 'Identifiant invalide' });

      const wasRemoved = await repository.remove(id);
      if (!wasRemoved) {
        return res.status(404).json({ error: 'Tâche introuvable' });
      }
      return res.status(204).end();
    }),
  );

  return router;
}

// /health : utilisé par les healthchecks Docker, le smoke test du CI et la supervision.
function createHealthHandler({ repository, appEnv, appVersion }) {
  return asyncHandler(async (_req, res) => {
    const isDbUp = await repository
      .ping()
      .then(() => true)
      .catch(() => false);

    res.status(isDbUp ? 200 : 503).json({
      status: isDbUp ? 'ok' : 'error',
      db: isDbUp ? 'up' : 'down',
      version: appVersion,
      env: appEnv,
    });
  });
}

export function createApp({
  repository,
  appEnv = 'local',
  appVersion = 'dev',
  log = writeLog,
  metrics = defaultMetrics,
}) {
  const { register, httpRequestsTotal, httpRequestDuration, buildInfo } =
    metrics;

  buildInfo.labels({ version: appVersion }).set(1);

  const app = express();

  // Middleware métriques : compteur + histogramme par route normalisée
  app.use((req, res, next) => {
    const end = httpRequestDuration.startTimer();
    res.on('finish', () => {
      const route = req.route ? `${req.baseUrl}${req.route.path}` : req.path;
      const labels = { method: req.method, route, status_code: res.statusCode };
      httpRequestsTotal.inc(labels);
      end(labels);
    });
    next();
  });

  app.use(createRequestLogger(log));
  app.use(express.json());

  app.get('/health', createHealthHandler({ repository, appEnv, appVersion }));
  app.use('/api/tasks', createTaskRoutes(repository, metrics));

  app.get('/metrics', async (_req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  });

  app.use((_req, res) => {
    res.status(404).json({ error: 'Route inconnue' });
  });

  // Gestionnaire d'erreurs (4 paramètres obligatoires pour qu'Express le reconnaisse).
  // On ne renvoie JAMAIS la stack trace au client : on la garde pour les logs.
  app.use((err, _req, res, _next) => {
    if (err.type === 'entity.parse.failed') {
      return res.status(400).json({ error: 'JSON invalide' });
    }
    log({ level: 'error', message: err.message });
    return res.status(500).json({ error: 'Erreur interne du serveur' });
  });

  return app;
}

// Métriques Prometheus exposées sur /metrics.
// createMetrics() reçoit un Registry : les tests passent le leur (pas de pollution entre tests).
import { Registry, Counter, Histogram, Gauge } from 'prom-client';

export function createMetrics(register = new Registry()) {
  // RED — Rate
  const httpRequestsTotal = new Counter({
    name: 'http_requests_total',
    help: 'Nombre de requêtes HTTP traitées',
    labelNames: ['method', 'route', 'status_code'],
    registers: [register],
  });

  // RED — Duration
  const httpRequestDuration = new Histogram({
    name: 'http_request_duration_seconds',
    help: 'Durée des requêtes HTTP en secondes',
    labelNames: ['method', 'route', 'status_code'],
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
    registers: [register],
  });

  // Métrique métier
  const tasksCreatedTotal = new Counter({
    name: 'taskflow_tasks_created_total',
    help: 'Nombre de tâches créées avec succès',
    registers: [register],
  });

  // Build info (version déployée)
  const buildInfo = new Gauge({
    name: 'taskflow_build_info',
    help: 'Informations de build',
    labelNames: ['version'],
    registers: [register],
  });

  return { register, httpRequestsTotal, httpRequestDuration, tasksCreatedTotal, buildInfo };
}

export const defaultMetrics = createMetrics();

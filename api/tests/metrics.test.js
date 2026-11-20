import request from 'supertest';
import { Registry } from 'prom-client';
import { beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { createMemoryRepository } from '../src/repositories/memory.js';
import { createMetrics } from '../src/metrics.js';

describe('GET /metrics', () => {
  let app;
  let metrics;

  beforeEach(() => {
    // Registry isolé par test : pas de pollution entre tests
    metrics = createMetrics(new Registry());
    app = createApp({
      repository: createMemoryRepository(),
      appVersion: '1.2.3',
      metrics,
    });
  });

  it('répond 200 avec le Content-Type Prometheus', async () => {
    const res = await request(app).get('/metrics');

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/plain/);
  });

  it('expose http_requests_total après une requête', async () => {
    await request(app).get('/api/tasks');

    const res = await request(app).get('/metrics');
    expect(res.text).toMatch(/http_requests_total/);
  });

  it('incrémente taskflow_tasks_created_total à chaque tâche créée', async () => {
    await request(app).post('/api/tasks').send({ title: 'Tâche test' });
    await request(app).post('/api/tasks').send({ title: 'Autre tâche' });

    const res = await request(app).get('/metrics');
    expect(res.text).toMatch(/taskflow_tasks_created_total 2/);
  });

  it('expose taskflow_build_info avec la version', async () => {
    const res = await request(app).get('/metrics');
    expect(res.text).toMatch(/taskflow_build_info\{version="1\.2\.3"\} 1/);
  });
});

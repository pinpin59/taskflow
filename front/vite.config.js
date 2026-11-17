import { defineConfig } from 'vite';

// En développement, le navigateur appelle /api/... sur le serveur Vite (port 5173).
// Le "proxy" redirige ces appels vers l'API (port 3000) : pas de problème de CORS.
const apiUrl = process.env.API_URL || 'http://localhost:3000';

export default defineConfig({
  server: {
    port: 5173,
    proxy: {
      '/api': apiUrl,
      '/health': apiUrl,
    },
  },
  test: {
    environment: 'node',
    // `npm run test:coverage` : couverture des fichiers de src/ (tableau console +
    // coverage/coverage-summary.json lu par le pipeline).
    coverage: {
      provider: 'v8',
      include: ['src/**/*.js'],
      reporter: ['text', 'json-summary'],
    },
  },
});

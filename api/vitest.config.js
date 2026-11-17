import { defineConfig } from 'vitest/config';

// Configuration des tests (Vitest). Utilisée par `npm test` et `npm run test:coverage`.
export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',
      include: ['src/**/*.js'],
      // Point d'entrée (lecture de la config, listen) : vérifié par le healthcheck
      // et le smoke test, pas par les tests unitaires.
      exclude: ['src/server.js'],
      // text : tableau dans la console ; json-summary : coverage/coverage-summary.json,
      // lu par le pipeline pour écrire le résumé et appliquer le seuil.
      reporter: ['text', 'json-summary'],
    },
  },
});

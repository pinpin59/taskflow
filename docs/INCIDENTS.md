# Incidents TaskFlow

## Méthode de diagnostic

1. Vérifier `http://localhost:9091/targets` — la cible est-elle UP ?
2. `docker ps --filter name=taskflow-staging` — les conteneurs tournent-ils ?
3. `docker logs taskflow-staging-api --tail 50` — y a-t-il des erreurs ?
4. `docker logs taskflow-staging-db --tail 20` — la base répond-elle ?

---

## INC-001 — API staging indisponible

**Date** : 2026-11-20  
**Durée** : ~2 minutes  
**Sévérité** : critique  
**Détection** : alerte `TaskFlowApiDown` (Alertmanager → Mailpit)

### Chronologie

| Heure | Évènement |
|---|---|
| 08:17 | `docker stop taskflow-staging-api` — API arrêtée volontairement |
| 08:18 | Blackbox détecte `/health` down — `probe_success = 0` |
| 08:19 | Alerte `TaskFlowApiDown` passe en `firing` après 1 minute |
| 08:20 | Mail reçu dans Mailpit |
| 08:21 | `docker start taskflow-staging-api` — API redémarrée |
| 08:22 | Alerte `resolved` — mail de résolution reçu |

### Cause racine

Arrêt manuel du conteneur `taskflow-staging-api` (simulation d'incident).

### Impact

- `/health` indisponible pendant ~2 minutes
- Aucune donnée perdue (base PostgreSQL non affectée)

### Actions correctives

- [x] Redémarrer le conteneur API
- [ ] Ajouter `restart: unless-stopped` dans la config Tofu (déjà présent — le conteneur redémarre seul en cas de crash)
- [ ] Vérifier que le monitoring détecte bien les pannes en moins de 2 minutes ✅

### Ce qui a bien fonctionné

- Alerte reçue en moins de 2 minutes
- Logs structurés JSON permettent un diagnostic rapide avec `jq`
- Base de données non affectée

### Action inacceptable (exemple)

> "Kevin ne touchera plus aux conteneurs en production."

### Action acceptable

> Le conteneur API redémarre automatiquement grâce à `restart: unless-stopped` — un crash ne nécessite plus d'intervention manuelle.

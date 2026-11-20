#!/usr/bin/env bash
# ============================================================================
# smoke-test.sh : « est-ce que la version déployée répond vraiment ? »
#
#     ./smoke-test.sh <url-de-/health> [version-attendue]
#
# Réussit si /health répond 200 avec status=ok, db=up ET (si fournie) la version
# attendue. Vérifier la version évite un faux vert : l'ANCIENNE version qui
# répond encore pendant que la nouvelle n'a pas démarré.
#
# Variables : SMOKE_RETRIES (20), SMOKE_DELAY (3 s), SMOKE_CURL_OPTS (options curl
# supplémentaires, ex. "--cacert /chemin/taskflow.crt" pour vérifier le certificat).
# ============================================================================
set -euo pipefail

URL="${1:?Usage: ./smoke-test.sh <url-de-/health> [version-attendue]}"
EXPECTED="${2:-}"
RETRIES="${SMOKE_RETRIES:-20}"
DELAY="${SMOKE_DELAY:-3}"
# shellcheck disable=SC2206  # découpage volontaire des options
CURL_OPTS=(${SMOKE_CURL_OPTS:-})

body=""
for i in $(seq 1 "$RETRIES"); do
  if body="$(curl -fsS --max-time 5 "${CURL_OPTS[@]}" "$URL" 2>&1)" \
     && jq -e --arg v "$EXPECTED" \
          '.status == "ok" and .db == "up" and ($v == "" or .version == $v)' \
          <<<"$body" >/dev/null 2>&1; then
    echo "Smoke test OK ($i/$RETRIES) : $body"
    exit 0
  fi
  echo "Essai $i/$RETRIES : pas encore bon -> ${body:0:200}"
  sleep "$DELAY"
done

echo "Smoke test ÉCHOUÉ sur $URL (version attendue : ${EXPECTED:-peu importe})" >&2
exit 1

#!/usr/bin/env bash
# ============================================================================
# gen-cert.sh : certificat HTTPS AUTO-SIGNÉ pour taskflow.localhost (lab).
#
# Le chiffrement est réel ; seule l'identité n'est garantie par aucune autorité,
# d'où l'avertissement du navigateur. Sur un vrai serveur : Let's Encrypt (certbot).
#
# Utilisation (dans PROD_DIR) :   ./gen-cert.sh
# Résultat : certs/taskflow.crt (public) et certs/taskflow.key (PRIVÉE, 600).
# Le SAN contient host.docker.internal : le smoke test du runner peut VÉRIFIER le
# certificat (curl --cacert certs/taskflow.crt) au lieu de l'ignorer (curl -k).
# Utilise openssl s'il est installé, sinon un conteneur Alpine.
# ============================================================================
set -euo pipefail

CERT_DIR="${CERT_DIR:-certs}"
DOMAIN="${DOMAIN:-taskflow.localhost}"
DAYS="${DAYS:-365}"

mkdir -p "$CERT_DIR"
if [[ -f "$CERT_DIR/taskflow.crt" && -f "$CERT_DIR/taskflow.key" && "${FORCE:-0}" != 1 ]]; then
  echo "Certificat déjà présent dans $CERT_DIR/ (FORCE=1 pour le régénérer)."
  exit 0
fi

ARGS=(req -x509 -nodes -newkey rsa:2048 -days "$DAYS"
  -keyout /out/taskflow.key -out /out/taskflow.crt
  -subj "/CN=$DOMAIN"
  -addext "subjectAltName=DNS:$DOMAIN,DNS:localhost,IP:127.0.0.1,DNS:host.docker.internal")

if command -v openssl >/dev/null 2>&1; then
  openssl "${ARGS[@]//\/out/$CERT_DIR}"
else
  docker run --rm -v "$(cd "$CERT_DIR" && pwd):/out" docker.io/library/alpine:3.21 \
    sh -c "apk add --no-cache openssl >/dev/null && openssl ${ARGS[*]@Q}"
fi

# Clé privée lisible par son seul propriétaire. Le processus maître de Nginx la
# lit en root dans le conteneur, cela suffit.
chmod 600 "$CERT_DIR/taskflow.key"
chmod 644 "$CERT_DIR/taskflow.crt"
echo "Certificat créé dans $CERT_DIR/ (valable $DAYS jours, pour $DOMAIN)"

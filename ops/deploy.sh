#!/usr/bin/env bash
# Déploie les stacks activées dans ops/config.sh, dans l'ordre.
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Ce script doit être exécuté en root (sudo)." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Charger la configuration des services
# shellcheck source=ops/config.sh
source "$ROOT_DIR/ops/config.sh"

ensure_network () {
  local name="$1"
  if ! docker network inspect "$name" >/dev/null 2>&1; then
    docker network create "$name"
    echo "[deploy] Réseau Docker créé : $name"
  fi
}

ensure_network proxy

# ---------------------------------------------------------------------------
# Traefik (en premier — fournit le réseau proxy et le TLS)
# ---------------------------------------------------------------------------
if [[ "${ENABLE_TRAEFIK}" == "true" ]]; then
  echo "[deploy] Traefik..."
  docker compose -f /opt/traefik/compose.yaml --env-file /opt/traefik/.env up -d
fi

# ---------------------------------------------------------------------------
# CrowdSec (sans bouncer pour l'instant)
# ---------------------------------------------------------------------------
if [[ "${ENABLE_CROWDSEC}" == "true" ]]; then
  echo "[deploy] CrowdSec (sans bouncer)..."
  docker compose -f /opt/crowdsec/compose.yaml --env-file /opt/crowdsec/.env up -d crowdsec
fi

# ---------------------------------------------------------------------------
# Applications
# ---------------------------------------------------------------------------
if [[ "${ENABLE_MATOMO}" == "true" ]]; then
  echo "[deploy] Matomo..."
  docker compose -f /opt/matomo/compose.yaml --env-file /opt/matomo/.env up -d
fi

if [[ "${ENABLE_VAULTWARDEN}" == "true" ]]; then
  echo "[deploy] Vaultwarden..."
  docker compose -f /opt/vaultwarden/compose.yaml --env-file /opt/vaultwarden/.env up -d
fi

if [[ "${ENABLE_UPTIME_KUMA}" == "true" ]]; then
  echo "[deploy] Uptime Kuma..."
  docker compose -f /opt/uptime-kuma/compose.yaml --env-file /opt/uptime-kuma/.env up -d
fi

if [[ "${ENABLE_WIKIJS}" == "true" ]]; then
  echo "[deploy] Wiki.js..."
  docker compose -f /opt/wikijs/compose.yaml --env-file /opt/wikijs/.env up -d
fi

# ---------------------------------------------------------------------------
# Watchtower (en dernier — surveille les conteneurs déjà démarrés)
# ---------------------------------------------------------------------------
if [[ "${ENABLE_WATCHTOWER}" == "true" ]]; then
  echo "[deploy] Watchtower..."
  docker compose -f /opt/watchtower/compose.yaml --env-file /opt/watchtower/.env up -d
fi

echo ""
echo "[deploy] Déploiement terminé."
echo ""
if [[ "${ENABLE_CROWDSEC}" == "true" ]]; then
  echo "Étape manuelle : activer le bouncer CrowdSec"
  echo "  1) docker exec kernet-crowdsec cscli bouncers add iptables-bouncer"
  echo "  2) Copier la clé dans /opt/crowdsec/.env  (CROWDSEC_BOUNCER_KEY=...)"
  echo "  3) docker compose -f /opt/crowdsec/compose.yaml --env-file /opt/crowdsec/.env up -d"
fi

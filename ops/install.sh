#!/usr/bin/env bash
# Initialise l'arborescence /opt/ et copie les templates de config.
# Idempotent : ne remplace jamais un fichier déjà présent.
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Ce script doit être exécuté en root (sudo)." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Charger la configuration des services
# shellcheck source=ops/config.sh
source "$ROOT_DIR/ops/config.sh"

# ---------------------------------------------------------------------------
# Fonction copie idempotente
# ---------------------------------------------------------------------------
copy_if_missing () {
  local src="$1"
  local dst="$2"
  local mode="${3:-0644}"
  if [[ -e "$dst" ]]; then
    echo "[install] déjà présent, ignoré : $dst"
    return 0
  fi
  install -D -m "$mode" "$src" "$dst"
  echo "[install] copié : $src -> $dst"
}

# ---------------------------------------------------------------------------
# Traefik (toujours requis)
# ---------------------------------------------------------------------------
if [[ "${ENABLE_TRAEFIK}" == "true" ]]; then
  echo "[install] Traefik..."
  mkdir -p /opt/traefik/{data,dynamic}
  if [[ ! -f /opt/traefik/data/acme.json ]]; then
    install -m 0600 /dev/null /opt/traefik/data/acme.json
    echo "[install] /opt/traefik/data/acme.json créé (600)"
  fi
  copy_if_missing "$ROOT_DIR/templates/traefik/compose.yaml"            /opt/traefik/compose.yaml
  copy_if_missing "$ROOT_DIR/templates/traefik/traefik.yml"             /opt/traefik/traefik.yml
  copy_if_missing "$ROOT_DIR/templates/traefik/dynamic/middlewares.yml" /opt/traefik/dynamic/middlewares.yml
  copy_if_missing "$ROOT_DIR/templates/traefik/dynamic/tls-options.yml" /opt/traefik/dynamic/tls-options.yml
  copy_if_missing "$ROOT_DIR/templates/traefik/env.example"             /opt/traefik/.env 0600
fi

# ---------------------------------------------------------------------------
# CrowdSec
# ---------------------------------------------------------------------------
if [[ "${ENABLE_CROWDSEC}" == "true" ]]; then
  echo "[install] CrowdSec..."
  mkdir -p /opt/crowdsec/{data,config}
  copy_if_missing "$ROOT_DIR/templates/crowdsec/compose.yaml"     /opt/crowdsec/compose.yaml
  copy_if_missing "$ROOT_DIR/templates/crowdsec/acquis.yaml"      /opt/crowdsec/config/acquis.yaml
  copy_if_missing "$ROOT_DIR/templates/crowdsec/profiles.yaml"    /opt/crowdsec/config/profiles.yaml
  copy_if_missing "$ROOT_DIR/templates/crowdsec/bouncer.yaml"     /opt/crowdsec/config/bouncer.yaml
  copy_if_missing "$ROOT_DIR/templates/crowdsec/env.example"      /opt/crowdsec/.env 0600
fi

# ---------------------------------------------------------------------------
# Matomo (nginx + postgres encapsulés)
# ---------------------------------------------------------------------------
if [[ "${ENABLE_MATOMO}" == "true" ]]; then
  echo "[install] Matomo..."
  mkdir -p /opt/matomo/{data,db,nginx}
  copy_if_missing "$ROOT_DIR/templates/matomo/compose.yaml"         /opt/matomo/compose.yaml
  copy_if_missing "$ROOT_DIR/templates/matomo/nginx/nginx.conf"     /opt/matomo/nginx/nginx.conf
  copy_if_missing "$ROOT_DIR/templates/matomo/env.example"          /opt/matomo/.env 0600
fi

# ---------------------------------------------------------------------------
# Vaultwarden (nginx + postgres encapsulés)
# ---------------------------------------------------------------------------
if [[ "${ENABLE_VAULTWARDEN}" == "true" ]]; then
  echo "[install] Vaultwarden..."
  mkdir -p /opt/vaultwarden/{data,db,nginx}
  copy_if_missing "$ROOT_DIR/templates/vaultwarden/compose.yaml"     /opt/vaultwarden/compose.yaml
  copy_if_missing "$ROOT_DIR/templates/vaultwarden/nginx/nginx.conf" /opt/vaultwarden/nginx/nginx.conf
  copy_if_missing "$ROOT_DIR/templates/vaultwarden/env.example"      /opt/vaultwarden/.env 0600
fi

# ---------------------------------------------------------------------------
# Uptime Kuma
# ---------------------------------------------------------------------------
if [[ "${ENABLE_UPTIME_KUMA}" == "true" ]]; then
  echo "[install] Uptime Kuma..."
  mkdir -p /opt/uptime-kuma/data
  copy_if_missing "$ROOT_DIR/templates/uptime-kuma/compose.yaml"    /opt/uptime-kuma/compose.yaml
  copy_if_missing "$ROOT_DIR/templates/uptime-kuma/env.example"     /opt/uptime-kuma/.env 0600
fi

# ---------------------------------------------------------------------------
# Wiki.js (nginx + postgres encapsulés)
# ---------------------------------------------------------------------------
if [[ "${ENABLE_WIKIJS}" == "true" ]]; then
  echo "[install] Wiki.js..."
  mkdir -p /opt/wikijs/{data,db,nginx}
  copy_if_missing "$ROOT_DIR/templates/wikijs/compose.yaml"         /opt/wikijs/compose.yaml
  copy_if_missing "$ROOT_DIR/templates/wikijs/nginx/nginx.conf"     /opt/wikijs/nginx/nginx.conf
  copy_if_missing "$ROOT_DIR/templates/wikijs/env.example"          /opt/wikijs/.env 0600
fi

# ---------------------------------------------------------------------------
# Watchtower
# ---------------------------------------------------------------------------
if [[ "${ENABLE_WATCHTOWER}" == "true" ]]; then
  echo "[install] Watchtower..."
  mkdir -p /opt/watchtower
  copy_if_missing "$ROOT_DIR/templates/watchtower/compose.yaml"    /opt/watchtower/compose.yaml
  copy_if_missing "$ROOT_DIR/templates/watchtower/env.example"     /opt/watchtower/.env 0600
fi

echo ""
echo "[install] Terminé."
echo ""
echo "Prochaines étapes :"
echo "  1) Éditer les .env dans /opt/*/.env (domaines, mots de passe, tokens)"
echo "  2) Préparer le système (swap, rsyslog, vim, timezone) :"
echo "       sudo TIMEZONE=Europe/Paris SWAP_SIZE_MB=2048 bash ops/system/setup-system.sh"
echo "  3) Mises à jour de sécurité Ubuntu + rotation des logs :"
echo "       sudo bash ops/system/setup-unattended-upgrades.sh"
echo "       sudo bash ops/system/setup-logrotate.sh"
echo "  4) Port SSH secondaire (220XX) :"
echo "       sudo SSH_EXTRA_PORT=220XX bash ops/ssh/setup-ports.sh"
echo "  5) Pare-feu :"
echo "       sudo SSH_PORT=22 SSH_EXTRA_PORT=220XX bash ops/firewall/setup-iptables.sh"
echo "  6) Déployer les stacks :"
echo "       sudo bash ops/deploy.sh"

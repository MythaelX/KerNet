#!/usr/bin/env bash
# Prépare le système Ubuntu pour un usage serveur :
#   - Swap (si absent)
#   - rsyslog (nécessaire pour /var/log/auth.log et CrowdSec SSH)
#   - vim comme éditeur par défaut
#   - Timezone
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Ce script doit être exécuté en root (sudo)." >&2
  exit 1
fi

TZ_SET="${TIMEZONE:-Europe/Paris}"
SWAP_SIZE_MB="${SWAP_SIZE_MB:-2048}"

# ---------------------------------------------------------------------------
# Timezone
# ---------------------------------------------------------------------------
echo "[system] Timezone → ${TZ_SET}"
timedatectl set-timezone "${TZ_SET}"
timedatectl set-ntp true

# ---------------------------------------------------------------------------
# Swap
# ---------------------------------------------------------------------------
if swapon --show | grep -q '/swapfile'; then
  echo "[system] Swap déjà configuré, ignoré."
else
  echo "[system] Création d'un swapfile de ${SWAP_SIZE_MB} Mo..."
  fallocate -l "${SWAP_SIZE_MB}M" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile

  if ! grep -q '/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi

  # Réduire swappiness (VPS : utiliser la RAM en priorité)
  sysctl vm.swappiness=10
  echo 'vm.swappiness=10' >> /etc/sysctl.d/99-kernet.conf
  echo "[system] Swap ${SWAP_SIZE_MB} Mo activé (swappiness=10)."
fi

# ---------------------------------------------------------------------------
# Packages : rsyslog + vim (un seul apt-get update)
# ---------------------------------------------------------------------------
PACKAGES_TO_INSTALL=()

if command -v rsyslogd >/dev/null 2>&1; then
  echo "[system] rsyslog déjà installé."
else
  PACKAGES_TO_INSTALL+=(rsyslog)
fi

if command -v vim >/dev/null 2>&1; then
  echo "[system] vim déjà installé."
else
  PACKAGES_TO_INSTALL+=(vim)
fi

if [[ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]]; then
  echo "[system] apt-get update..."
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  echo "[system] Installation : ${PACKAGES_TO_INSTALL[*]}..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES_TO_INSTALL[@]}"
fi

if command -v rsyslogd >/dev/null 2>&1; then
  systemctl enable --now rsyslog
  echo "[system] rsyslog actif. /var/log/auth.log disponible."
fi
update-alternatives --set editor /usr/bin/vim.basic 2>/dev/null || true

# ---------------------------------------------------------------------------
# Résumé
# ---------------------------------------------------------------------------
echo ""
echo "[system] Configuration système terminée."
echo "  Timezone : $(timedatectl show -p Timezone --value)"
echo "  Swap     : $(swapon --show --noheadings 2>/dev/null | awk '{print $3}' | head -1 || echo 'aucun')"
echo "  rsyslog  : $(systemctl is-active rsyslog 2>/dev/null || echo 'inactif')"
echo "  vim      : $(command -v vim)"

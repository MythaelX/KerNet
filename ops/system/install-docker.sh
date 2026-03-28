#!/usr/bin/env bash
# Installe Docker Engine + Docker Compose (plugin) sur Ubuntu.
# Méthode officielle Docker Inc. — apt repository.
# Idempotent : si Docker est déjà installé, le script se termine sans rien faire.
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Ce script doit être exécuté en root (sudo)." >&2
  exit 1
fi

if command -v docker >/dev/null 2>&1; then
  echo "[docker] Docker est déjà installé : $(docker --version)"
  echo "[docker] Rien à faire."
  exit 0
fi

echo "[docker] Installation des dépendances..."
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release

echo "[docker] Ajout de la clé GPG officielle Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "[docker] Ajout du dépôt Docker..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list >/dev/null

echo "[docker] Installation de Docker Engine + Compose plugin..."
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

systemctl enable --now docker

echo ""
echo "[docker] Installation terminée."
docker --version
docker compose version
echo ""
echo "Pour autoriser un utilisateur non-root à utiliser Docker (optionnel) :"
echo "  sudo usermod -aG docker <user>   # puis se reconnecter"

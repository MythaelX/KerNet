#!/usr/bin/env bash
# Configure la rotation des logs Traefik (access.log).
# Traefik utilise le mode append : copytruncate évite de devoir lui envoyer un signal.
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Ce script doit être exécuté en root (sudo)." >&2
  exit 1
fi

cat >/etc/logrotate.d/kernet-traefik <<'EOF'
/opt/traefik/data/access.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    # copytruncate : copie le fichier puis vide l'original (pas besoin de signal)
    copytruncate
    create 0644 root root
}
EOF

echo "[logrotate] Config écrite : /etc/logrotate.d/kernet-traefik"
echo "Test : sudo logrotate -d /etc/logrotate.d/kernet-traefik"

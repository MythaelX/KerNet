#!/usr/bin/env bash
# Configure sshd pour écouter sur le port 22 ET un port secondaire (ex: 22047).
# Le port 22 reste ouvert ; tu le fermeras manuellement (firewall + sshd) une
# fois que tu auras vérifié que le port secondaire fonctionne.
#
# Usage:
#   sudo SSH_EXTRA_PORT=22047 bash ops/ssh/setup-ports.sh
#
# La valeur SSH_EXTRA_PORT doit correspondre aux derniers chiffres de l'IP du VPS.
# Exemple : IP = x.x.x.47  →  SSH_EXTRA_PORT=22047
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Ce script doit être exécuté en root (sudo)." >&2
  exit 1
fi

if [[ -z "${SSH_EXTRA_PORT:-}" ]]; then
  echo "Usage: SSH_EXTRA_PORT=220XX sudo bash ops/ssh/setup-ports.sh" >&2
  echo "Exemple (IP x.x.x.47): SSH_EXTRA_PORT=22047 sudo bash ops/ssh/setup-ports.sh" >&2
  exit 1
fi

# Validation basique du port
if ! [[ "$SSH_EXTRA_PORT" =~ ^[0-9]+$ ]] || (( SSH_EXTRA_PORT < 1024 || SSH_EXTRA_PORT > 65535 )); then
  echo "SSH_EXTRA_PORT doit être un entier entre 1024 et 65535." >&2
  exit 1
fi

CONFIG_FILE="/etc/ssh/sshd_config.d/50-kernet-ports.conf"

install -d -m 0755 /etc/ssh/sshd_config.d

cat >"$CONFIG_FILE" <<EOF
# Géré par KerNet ops/ssh/setup-ports.sh
# Port 22 conservé le temps de vérifier le port secondaire.
# Ferme le port 22 MANUELLEMENT après validation :
#   1) Supprime ou commente "Port 22" dans ce fichier
#   2) Relance: systemctl reload ssh
#   3) Mets à jour le firewall: iptables -D INPUT -p tcp --dport 22 ...
Port 22
Port ${SSH_EXTRA_PORT}
EOF

echo "[ssh] Configuration écrite : $CONFIG_FILE"
cat "$CONFIG_FILE"

# Vérification de la syntaxe sshd avant rechargement
if sshd -t; then
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  echo ""
  echo "[ssh] sshd rechargé. Ports actifs : 22 et ${SSH_EXTRA_PORT}"
  echo ""
  echo "Test depuis un autre terminal AVANT de fermer cette session :"
  echo "  ssh -p ${SSH_EXTRA_PORT} <user>@<ip>"
  echo ""
  echo "Une fois validé, pour fermer le port 22 :"
  echo "  1) Édite $CONFIG_FILE  →  supprime la ligne 'Port 22'"
  echo "  2) systemctl reload ssh"
  echo "  3) iptables -D INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m limit --limit 6/min --limit-burst 10 -j ACCEPT"
  echo "  4) netfilter-persistent save"
else
  echo "[ssh] ERREUR de syntaxe sshd_config — aucune modification appliquée." >&2
  rm -f "$CONFIG_FILE"
  exit 1
fi

#!/usr/bin/env bash
# Configure sshd pour écouter sur le port 22 ET un port secondaire (ex: 22047).
#
# Ubuntu 22.04+ utilise la socket activation systemd par défaut :
#   le port est géré par ssh.socket, PAS par sshd_config.
#   Ce script détecte le mode et s'adapte.
#
# Usage:
#   sudo SSH_EXTRA_PORT=22047 bash ops/ssh/setup-ports.sh
#
# Convention : SSH_EXTRA_PORT = 220XX (derniers chiffres de l'IP du VPS)
# Exemple : IP x.x.x.47  →  SSH_EXTRA_PORT=22047
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Ce script doit être exécuté en root (sudo)." >&2
  exit 1
fi

if [[ -z "${SSH_EXTRA_PORT:-}" ]]; then
  echo "Usage: sudo SSH_EXTRA_PORT=220XX bash ops/ssh/setup-ports.sh" >&2
  echo "Exemple (IP x.x.x.47): sudo SSH_EXTRA_PORT=22047 bash ops/ssh/setup-ports.sh" >&2
  exit 1
fi

if ! [[ "$SSH_EXTRA_PORT" =~ ^[0-9]+$ ]] || (( SSH_EXTRA_PORT < 1024 || SSH_EXTRA_PORT > 65535 )); then
  echo "SSH_EXTRA_PORT doit être un entier entre 1024 et 65535." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Détection du mode : socket activation ou daemon classique
# ---------------------------------------------------------------------------
USE_SOCKET=false
if systemctl is-active ssh.socket >/dev/null 2>&1; then
  USE_SOCKET=true
  echo "[ssh] Mode détecté : socket activation (Ubuntu 22.04+)"
else
  echo "[ssh] Mode détecté : daemon sshd classique"
fi

# ---------------------------------------------------------------------------
# Mode socket activation (Ubuntu 22.04 / 24.04 / 25.xx)
# Le port est géré par ssh.socket, pas par sshd_config.
# ---------------------------------------------------------------------------
if $USE_SOCKET; then
  SOCKET_OVERRIDE_DIR="/etc/systemd/system/ssh.socket.d"
  SOCKET_OVERRIDE_FILE="${SOCKET_OVERRIDE_DIR}/kernet-ports.conf"

  mkdir -p "$SOCKET_OVERRIDE_DIR"

  cat >"$SOCKET_OVERRIDE_FILE" <<EOF
[Socket]
# Réinitialise la liste des ports avant d'en ajouter (syntaxe systemd)
ListenStream=
ListenStream=22
ListenStream=${SSH_EXTRA_PORT}
EOF

  echo "[ssh] Override socket écrit : $SOCKET_OVERRIDE_FILE"
  cat "$SOCKET_OVERRIDE_FILE"

  systemctl daemon-reload
  systemctl restart ssh.socket

  echo ""
  echo "[ssh] ssh.socket redémarré. Ports actifs : 22 et ${SSH_EXTRA_PORT}"

# ---------------------------------------------------------------------------
# Mode daemon classique (Ubuntu < 22.04 ou socket activation désactivée)
# ---------------------------------------------------------------------------
else
  CONFIG_FILE="/etc/ssh/sshd_config.d/50-kernet-ports.conf"
  install -d -m 0755 /etc/ssh/sshd_config.d

  cat >"$CONFIG_FILE" <<EOF
# Géré par KerNet ops/ssh/setup-ports.sh
Port 22
Port ${SSH_EXTRA_PORT}
EOF

  echo "[ssh] Config sshd écrite : $CONFIG_FILE"

  if ! sshd -t; then
    echo "[ssh] ERREUR de syntaxe sshd_config — annulation." >&2
    rm -f "$CONFIG_FILE"
    exit 1
  fi

  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  echo ""
  echo "[ssh] sshd rechargé. Ports actifs : 22 et ${SSH_EXTRA_PORT}"
fi

# ---------------------------------------------------------------------------
# Vérification que les deux ports écoutent
# ---------------------------------------------------------------------------
echo ""
echo "Vérification des ports en écoute :"
ss -tlnp | grep -E ":(22|${SSH_EXTRA_PORT})\b" || echo "(aucun résultat — attendre quelques secondes et relancer)"

echo ""
echo "Test depuis un autre terminal AVANT de fermer cette session :"
echo "  ssh -p ${SSH_EXTRA_PORT} <user>@<ip>"
echo ""

# ---------------------------------------------------------------------------
# Instructions pour fermer le port 22 ensuite
# ---------------------------------------------------------------------------
if $USE_SOCKET; then
  echo "Pour fermer le port 22 après validation :"
  echo "  1) Édite ${SOCKET_OVERRIDE_FILE}"
  echo "     → supprime la ligne 'ListenStream=22'"
  echo "  2) systemctl daemon-reload && systemctl restart ssh.socket"
  echo "  3) iptables -D INPUT -p tcp --dport 22 ..."
  echo "     netfilter-persistent save"
else
  echo "Pour fermer le port 22 après validation :"
  echo "  1) Édite /etc/ssh/sshd_config.d/50-kernet-ports.conf"
  echo "     → supprime la ligne 'Port 22'"
  echo "  2) systemctl reload ssh"
  echo "  3) iptables -D INPUT -p tcp --dport 22 ..."
  echo "     netfilter-persistent save"
fi

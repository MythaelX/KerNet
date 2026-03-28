#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Exécute ce script en tant qu’utilisateur cible, pas root." >&2
  echo "Exemple: sudo -u <user> bash ops/ssh-2fa/init-user.sh" >&2
  exit 1
fi

if command -v google-authenticator >/dev/null 2>&1; then
  :
else
  echo "google-authenticator introuvable. Exécute d’abord: sudo bash ops/ssh-2fa/setup.sh" >&2
  exit 1
fi

echo "Lancement de google-authenticator (interactif)."
echo "Choix recommandés:"
echo "- time-based tokens: yes"
echo "- update ~/.google_authenticator: yes"
echo "- disallow multiple uses: yes"
echo "- increase window: no (sauf problème horloge)"
echo "- enable rate-limiting: yes"

google-authenticator

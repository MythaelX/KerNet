#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Ce script doit être exécuté en root (sudo)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y libpam-google-authenticator

install -d -m 0755 /etc/ssh/sshd_config.d

cat >/etc/ssh/sshd_config.d/50-kernet-2fa.conf <<'EOF'
# Géré par KerNet ops/ssh-2fa/setup.sh
KbdInteractiveAuthentication yes

# Autorise soit:
# - clé SSH + OTP
# - mot de passe + OTP
AuthenticationMethods publickey,keyboard-interactive password,keyboard-interactive

# Recommandations minimales
PermitRootLogin prohibit-password
UsePAM yes
EOF

if ! grep -q 'pam_google_authenticator\.so' /etc/pam.d/sshd; then
  # Sans "user=root" : chaque user lit son propre ~/.google_authenticator
  # "nullok" permet la connexion si le user n'a pas encore initialisé son OTP
  # (à retirer une fois que tous les users ont exécuté init-user.sh)
  PAM_LINE='auth required pam_google_authenticator.so nullok'

  if grep -q '^@include common-auth' /etc/pam.d/sshd; then
    sed -i '/^@include common-auth/a '"${PAM_LINE}" /etc/pam.d/sshd
  else
    echo "${PAM_LINE}" >> /etc/pam.d/sshd
  fi
fi

systemctl reload ssh || systemctl reload sshd || true

echo "Config SSH 2FA appliquée."
echo ""
echo "IMPORTANT : nullok est actif — les users sans OTP peuvent encore se connecter."
echo "Une fois que tous les users ont lancé ops/ssh-2fa/init-user.sh, retire 'nullok' :"
echo "  sudo vim /etc/pam.d/sshd"
echo "  → remplace 'nullok' par rien sur la ligne pam_google_authenticator.so"
echo "  sudo systemctl reload ssh"
echo ""
echo "Prochaine étape: initialiser chaque utilisateur avec ops/ssh-2fa/init-user.sh"

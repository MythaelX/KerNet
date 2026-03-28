#!/usr/bin/env bash
# Active les mises à jour automatiques de sécurité Ubuntu (patches uniquement).
# Pas de mise à jour des paquets applicatifs, pas de reboot automatique.
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Ce script doit être exécuté en root (sudo)." >&2
  exit 1
fi

DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades apt-listchanges

# Configuration principale
cat >/etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

// Pas de mise à jour de paquets non-sécurité
Unattended-Upgrade::Package-Blacklist {
};

// Ne pas redémarrer automatiquement
Unattended-Upgrade::Automatic-Reboot "false";

// Retirer les paquets inutiles après mise à jour
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";

// Logs verbeux
Unattended-Upgrade::Verbose "false";
Unattended-Upgrade::Debug "false";
EOF

# Activation de la tâche périodique
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

systemctl enable --now unattended-upgrades

echo "[system] unattended-upgrades activé (patches de sécurité uniquement)."
echo "Logs : /var/log/unattended-upgrades/"
echo ""
echo "Test manuel : sudo unattended-upgrade --dry-run --verbose"

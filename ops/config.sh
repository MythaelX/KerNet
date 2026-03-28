#!/usr/bin/env bash
# ============================================================
# KerNet — Configuration des services à installer / déployer
# ============================================================
# Ce fichier est sourcé par ops/install.sh et ops/deploy.sh.
# Mets à "false" tout service que tu ne veux PAS sur ce VPS.
# ============================================================

# --- Infra (ne désactive que si tu sais ce que tu fais) ---
ENABLE_TRAEFIK=true
ENABLE_CROWDSEC=true
ENABLE_WATCHTOWER=true

# --- Applications ---
ENABLE_MATOMO=true
ENABLE_VAULTWARDEN=true
ENABLE_UPTIME_KUMA=true
ENABLE_WIKIJS=false

# KerNet — Template infra VPS OVH (Ubuntu + Docker)

Base de dépôt réutilisable pour déployer rapidement une infra Docker sécurisée sur un VPS OVH Ubuntu.

## Stack incluse

| Service | Rôle | Activé par défaut |
|---------|------|:-----------------:|
| **Traefik v3** | Reverse proxy + Let's Encrypt automatique | ✅ |
| **CrowdSec** | Détection d'intrusion + bouncer iptables | ✅ |
| **Matomo** | Analytics web | ✅ |
| **Vaultwarden** | Gestionnaire de mots de passe (Bitwarden compatible) | ✅ |
| **Uptime Kuma** | Monitoring / alertes uptime | ✅ |
| **Watchtower** | Mise à jour automatique des images Docker (3h) | ✅ |
| **Wiki.js** | Wiki collaboratif (docs internes) | ❌ |

---

## Choisir ses services — `ops/config.sh`

Avant de lancer `install.sh`, édite `ops/config.sh` pour activer ou désactiver les services :

```bash
vim ops/config.sh
```

```bash
# --- Infra (ne désactive que si tu sais ce que tu fais) ---
ENABLE_TRAEFIK=true
ENABLE_CROWDSEC=true
ENABLE_WATCHTOWER=true

# --- Applications ---
ENABLE_MATOMO=true
ENABLE_VAULTWARDEN=true
ENABLE_UPTIME_KUMA=true
ENABLE_WIKIJS=false        # ← mettre true pour activer Wiki.js
```

`install.sh` et `deploy.sh` lisent ce fichier et ignorent les services à `false`. Le choix est **idempotent** : tu peux relancer les scripts à tout moment pour ajouter un service oublié.

---

## Architecture réseau

```
Internet
    │
    ▼
[iptables — DROP par défaut, ports 22/220XX/80/443 ouverts]
    │
    ▼
[Traefik :80/:443]  ←  TLS Let's Encrypt, security headers, rate limiting, BasicAuth
    │
    │  réseau Docker : proxy (partagé — seuls les nginx/apps exposées y ont accès)
    │
    ├── [matomo-nginx]          réseau interne : matomo_internal
    │       ├── matomo-app (PHP-FPM)
    │       └── matomo-db (PostgreSQL 16)
    │
    ├── [vaultwarden-nginx]     réseau interne : vaultwarden_internal
    │       ├── vaultwarden-app
    │       └── vaultwarden-db (PostgreSQL 16)
    │
    ├── [wikijs-nginx]          réseau interne : wikijs_internal
    │       ├── wikijs-app (Node.js)
    │       └── wikijs-db (PostgreSQL 16)
    │
    └── [uptime-kuma]

[CrowdSec] ← lit /opt/traefik/data/access.log + /var/log/auth.log
[iptables-bouncer] ← network_mode: host → écrit les règles iptables directement
[Watchtower] ← surveille uniquement les conteneurs labelisés watchtower.enable=true
```

Chaque application est **totalement encapsulée** : sa propre base PostgreSQL, son propre nginx, son propre réseau Docker interne. Aucun service partagé entre apps.

---

## Prérequis

- VPS OVH **Ubuntu** (testé sur Ubuntu 25)
- Ports **80** et **443** ouverts (nécessaire pour Let's Encrypt HTTP-01)
- Un nom de domaine avec sous-domaines pointant vers l'IP du VPS
- Accès SSH root ou sudo

---

## Structure du dépôt

```
ops/
  config.sh                   # ← Activer / désactiver les services ici
  system/
    install-docker.sh           # Installe Docker Engine + Compose (méthode officielle)
    setup-system.sh             # Swap, rsyslog, vim, timezone (à lancer en premier)
    setup-unattended-upgrades.sh # Patches de sécurité Ubuntu automatiques
    setup-logrotate.sh          # Rotation des logs Traefik (daily, 14 jours)
  firewall/
    setup-iptables.sh           # Pare-feu iptables (IPv4 + IPv6, DROP par défaut)
    README.md
  ssh/
    setup-ports.sh              # Configure sshd sur port 22 + port 220XX
  ssh-2fa/
    setup.sh                    # Active SSH + OTP Google Authenticator (tous les users)
    init-user.sh                # Génère le secret OTP pour un utilisateur
    README.md
  install.sh                    # Crée /opt/* et copie les templates (idempotent)
  deploy.sh                     # Lance les stacks activées dans l'ordre

templates/
  traefik/
    compose.yaml
    traefik.yml
    dynamic/
      middlewares.yml           # Security headers + rate limiting (pas de vars d'env ici)
      tls-options.yml
    env.example
  crowdsec/
    compose.yaml
    acquis.yaml                 # Sources de logs (Traefik + SSH)
    profiles.yaml               # Politique de ban (4h par défaut)
    bouncer.yaml                # Config du bouncer iptables (fichier requis par l'image)
    env.example
  matomo/
    compose.yaml                # matomo-app (FPM) + matomo-nginx + matomo-db
    nginx/nginx.conf
    env.example
  vaultwarden/
    compose.yaml                # vaultwarden-app + vaultwarden-nginx + vaultwarden-db
    nginx/nginx.conf
    env.example
  uptime-kuma/
    compose.yaml
    env.example
  wikijs/
    compose.yaml                # wikijs-app (Node.js) + wikijs-nginx + wikijs-db
    nginx/nginx.conf
    env.example
  watchtower/
    compose.yaml
    env.example

secrets/                        # Secrets SOPS (*.enc.yaml commités, .env jamais)
  README.md
```

---

## Déploiement complet (ordre à respecter)

### Étape 0 — Choisir ses services

```bash
vim ops/config.sh
# Mettre true/false selon ce que tu veux installer
```

### Étape 1 — Cloner le repo sur le VPS

```bash
git clone <url-repo> /opt/kernet
cd /opt/kernet
```

### Étape 2 — Installer Docker

```bash
sudo bash ops/system/install-docker.sh
```

### Étape 3 — Initialiser les dossiers et templates

```bash
sudo bash ops/install.sh
```

Seuls les services activés dans `config.sh` sont installés.

### Étape 4 — Configurer les .env

```bash
# Traefik
sudo vim /opt/traefik/.env

# Matomo (si activé)
sudo vim /opt/matomo/.env

# Vaultwarden (si activé)
sudo vim /opt/vaultwarden/.env

# Uptime Kuma (si activé)
sudo vim /opt/uptime-kuma/.env

# Wiki.js (si activé)
sudo vim /opt/wikijs/.env

# CrowdSec (la clé bouncer se génère après démarrage)
sudo vim /opt/crowdsec/.env
```

> **Générer le hash BasicAuth Traefik** :
> ```bash
> htpasswd -nbB admin 'ton_mot_de_passe'
> # Coller le résultat dans TRAEFIK_DASHBOARD_BASIC_AUTH
> # Dans .env, doubler les $ : $2y$ → $$2y$$
> ```

> **Générer l'admin token Vaultwarden** :
> ```bash
> openssl rand -base64 48
> ```

### Étape 5 — Préparer le système

```bash
# Swap (2 Go par défaut), rsyslog (requis pour auth.log/CrowdSec), vim, timezone
sudo TIMEZONE=Europe/Paris SWAP_SIZE_MB=2048 bash ops/system/setup-system.sh

# Mises à jour de sécurité automatiques + rotation des logs Traefik
sudo bash ops/system/setup-unattended-upgrades.sh
sudo bash ops/system/setup-logrotate.sh
```

### Étape 6 — Port SSH secondaire

Convention : `220XX` où `XX` = derniers chiffres de l'IP du VPS.
Exemple pour IP `x.x.x.47` → port `22047`.

```bash
sudo SSH_EXTRA_PORT=22047 bash ops/ssh/setup-ports.sh
```

**Tester le nouveau port dans un second terminal avant de continuer.**

### Étape 7 — Pare-feu iptables

```bash
sudo SSH_PORT=22 SSH_EXTRA_PORT=22047 bash ops/firewall/setup-iptables.sh
```

### Étape 8 — SSH + 2FA Google Authenticator

```bash
# Activer le module PAM (une fois, en root)
sudo bash ops/ssh-2fa/setup.sh

# Pour chaque utilisateur qui doit se connecter
sudo -u <user> bash ops/ssh-2fa/init-user.sh
```

Scanner le QR code avec Google Authenticator, puis tester la connexion.

> Une fois **tous** les users initialisés, retirer `nullok` de `/etc/pam.d/sshd` pour rendre le 2FA obligatoire :
> ```bash
> sudo vim /etc/pam.d/sshd
> # → supprimer "nullok" sur la ligne pam_google_authenticator.so
> sudo systemctl reload ssh
> ```

### Étape 9 — Déployer les stacks

```bash
sudo bash ops/deploy.sh
```

### Étape 10 — Activer le bouncer CrowdSec

```bash
# Générer la clé
docker exec kernet-crowdsec cscli bouncers add iptables-bouncer
# → Copier la clé affichée dans /opt/crowdsec/.env (CROWDSEC_BOUNCER_KEY=...)

# Démarrer le bouncer
docker compose -f /opt/crowdsec/compose.yaml --env-file /opt/crowdsec/.env up -d
```

### Étape 11 — Fermer le port SSH 22 (après validation du port secondaire)

```bash
# 1. Supprimer "Port 22" dans la config sshd
sudo vim /etc/ssh/sshd_config.d/50-kernet-ports.conf
sudo systemctl reload ssh

# 2. Mettre à jour le firewall
sudo iptables -D INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m limit --limit 6/min --limit-burst 10 -j ACCEPT
sudo ip6tables -D INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m limit --limit 6/min --limit-burst 10 -j ACCEPT
sudo netfilter-persistent save
```

---

## Gestion quotidienne

### Vérifier l'état des stacks

```bash
docker ps
docker compose -f /opt/traefik/compose.yaml ps
```

### Mettre à jour manuellement une image

```bash
docker compose -f /opt/matomo/compose.yaml --env-file /opt/matomo/.env pull
docker compose -f /opt/matomo/compose.yaml --env-file /opt/matomo/.env up -d
```

Watchtower le fait automatiquement à 3h du matin pour toutes les stacks labelisées.

### Voir les IPs bloquées par CrowdSec

```bash
docker exec kernet-crowdsec cscli decisions list
# Débloquer une IP :
docker exec kernet-crowdsec cscli decisions delete --ip <IP>
```

### Logs Traefik

```bash
tail -f /opt/traefik/data/access.log
```

---

## Ajouter un nouveau service

1. Éditer `ops/config.sh` : ajouter `ENABLE_MONSERVICE=false`
2. Créer `templates/<service>/compose.yaml` en suivant le pattern existant :
   - Réseau interne dédié (`<service>_internal`, `internal: true`)
   - PostgreSQL si besoin (avec healthcheck)
   - nginx si PHP-FPM ou besoin d'un proxy interne
   - Réseau `proxy` external uniquement sur le conteneur exposé
   - Labels Traefik : rule, tls, certresolver, middlewares (`security-headers@file` + `rate-limit-public@file` si public)
   - Label Watchtower : `com.centurylinklabs.watchtower.enable=true` sur **tous** les conteneurs
   - Un seul bloc `labels:` par service (deux blocs = le second écrase le premier)
3. Créer `templates/<service>/env.example`
4. Ajouter le bloc conditionnel dans `ops/install.sh` et `ops/deploy.sh`

---

## Sécurité — rappels

| Point | Statut |
|-------|--------|
| Pare-feu DROP par défaut | ✅ iptables IPv4 + IPv6 |
| Docker ne bypass pas iptables | ✅ Chaîne DOCKER-USER |
| TLS 1.2 minimum | ✅ `tls-options.yml` |
| Security headers HTTP | ✅ Middleware Traefik |
| Rate limiting public | ✅ 100 req/s par IP |
| Blocage automatique IPs malveillantes | ✅ CrowdSec + bouncer iptables |
| Mises à jour sécurité OS | ✅ unattended-upgrades |
| Mises à jour images Docker | ✅ Watchtower (3h, opt-in label) |
| 2FA SSH | ✅ Google Authenticator (PAM) |
| Secrets non commités | ✅ .gitignore + SOPS prévu |
| Rotation des logs | ✅ logrotate daily 14j |

---

## Variables d'environnement — référence rapide

### `/opt/traefik/.env`

| Variable | Description | Exemple |
|----------|-------------|---------|
| `TZ` | Fuseau horaire | `Europe/Paris` |
| `LETSENCRYPT_EMAIL` | Email pour Let's Encrypt | `admin@example.tld` |
| `TRAEFIK_DASHBOARD_HOST` | Sous-domaine dashboard | `traefik.example.tld` |
| `TRAEFIK_DASHBOARD_BASIC_AUTH` | Hash htpasswd bcrypt | `admin:$$2y$$...` |

### `/opt/matomo/.env`

| Variable | Description |
|----------|-------------|
| `MATOMO_HOST` | Sous-domaine Matomo |
| `MATOMO_DB_NAME` / `MATOMO_DB_USER` / `MATOMO_DB_PASSWORD` | PostgreSQL dédié |

### `/opt/vaultwarden/.env`

| Variable | Description |
|----------|-------------|
| `VAULTWARDEN_HOST` | Sous-domaine Vaultwarden |
| `VAULTWARDEN_SIGNUPS_ALLOWED` | `false` recommandé |
| `VAULTWARDEN_ADMIN_TOKEN` | Token admin (`openssl rand -base64 48`) |
| `VW_DB_NAME` / `VW_DB_USER` / `VW_DB_PASSWORD` | PostgreSQL dédié |

### `/opt/wikijs/.env`

| Variable | Description |
|----------|-------------|
| `WIKIJS_HOST` | Sous-domaine Wiki.js |
| `WIKIJS_DB_NAME` / `WIKIJS_DB_USER` / `WIKIJS_DB_PASSWORD` | PostgreSQL dédié |

### `/opt/uptime-kuma/.env`

| Variable | Description |
|----------|-------------|
| `UPTIME_KUMA_HOST` | Sous-domaine Uptime Kuma |

### `/opt/crowdsec/.env`

| Variable | Description |
|----------|-------------|
| `CROWDSEC_COLLECTIONS` | Ex: `crowdsecurity/traefik crowdsecurity/sshd` |
| `CROWDSEC_BOUNCER_KEY` | Clé générée via `cscli bouncers add` |

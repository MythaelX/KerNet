# CLAUDE.md — Contexte projet KerNet

Ce fichier donne à Claude le contexte nécessaire pour m'aider efficacement sur ce projet.

---

## Objectif du projet

Template de dépôt Git pour déployer rapidement une infra Docker sécurisée sur un VPS OVH Ubuntu.
Réutilisable pour plusieurs VPS : chaque VPS clone le repo, adapte ses `.env`, lance les scripts.

---

## Stack technique

| Technologie | Rôle | Version |
|-------------|------|---------|
| Ubuntu | OS VPS | 25 |
| Docker Engine + Compose plugin | Conteneurs | latest stable |
| Traefik | Reverse proxy + TLS | v3.3 |
| CrowdSec | IDS + bouncer iptables | latest |
| Matomo | Analytics | 5-fpm |
| Vaultwarden | Gestionnaire mdp (Bitwarden) | latest |
| Wiki.js | Wiki collaboratif | 2 |
| Uptime Kuma | Monitoring uptime | 1 |
| Watchtower | Mise à jour images Docker | latest |
| PostgreSQL | Base de données | 16 |
| nginx | Proxy interne par app | 1.27-alpine |

---

## Architecture — règles importantes

### Encapsulation par app
Chaque application a ses propres services Docker :
- **Son propre PostgreSQL** (pas de base partagée)
- **Son propre nginx** (sauf Uptime Kuma qui est Node.js)
- **Son propre réseau Docker interne** (ex: `matomo_internal`, `vaultwarden_internal`)
- Seul le conteneur nginx/app est connecté au réseau `proxy` (partagé avec Traefik)

### Réseau `proxy`
- Réseau Docker **externe** créé manuellement avant deploy
- Seuls Traefik + les conteneurs exposés y ont accès
- Les bases PostgreSQL et les apps FPM ne sont jamais sur ce réseau

### Traefik — particularité importante
Le **file provider** de Traefik (`/etc/traefik/dynamic/*.yml`) **ne fait pas de substitution
de variables d'environnement**. Conséquence :
- Les middlewares qui ont besoin de valeurs dynamiques (ex: BasicAuth) doivent être définis
  en **labels Docker** dans `compose.yaml` (où les env vars fonctionnent)
- Seuls les middlewares **statiques** (security headers, rate limiting) sont dans les fichiers `.yml`
- Dans `compose.yaml`, les middlewares du file provider sont référencés avec le suffixe `@file`
  (ex: `security-headers@file`), ceux des labels Docker avec `@docker` (ex: `traefik-auth@docker`)

### Watchtower — opt-in
Watchtower ne met à jour que les conteneurs avec le label :
```
com.centurylinklabs.watchtower.enable=true
```
Tous les conteneurs du projet ont ce label. Si tu ajoutes un nouveau service, pense à l'inclure.

### CrowdSec — ordre de déploiement
1. Démarrer CrowdSec (sans bouncer)
2. Générer la clé bouncer : `docker exec kernet-crowdsec cscli bouncers add iptables-bouncer`
3. Renseigner la clé dans `.env`, redémarrer avec le bouncer

---

## Activation des services — `ops/config.sh`

Chaque service a un flag `ENABLE_<SERVICE>=true/false` dans `ops/config.sh`.
`install.sh` et `deploy.sh` sourcent ce fichier et traitent uniquement les services actifs.

```bash
ENABLE_TRAEFIK=true       # Toujours requis
ENABLE_CROWDSEC=true
ENABLE_WATCHTOWER=true
ENABLE_MATOMO=true
ENABLE_VAULTWARDEN=true
ENABLE_UPTIME_KUMA=true
ENABLE_WIKIJS=false        # Désactivé par défaut
```

Pour ajouter un nouveau service : ajouter `ENABLE_MONSERVICE=false` dans `config.sh`, créer le template, ajouter les blocs conditionnels dans `install.sh` et `deploy.sh`.

## Structure des fichiers

```
ops/
  config.sh               # ← Flags d'activation des services
  install.sh              # Idempotent, source config.sh
  deploy.sh               # Lance les stacks activées, source config.sh
  system/
    install-docker.sh
    setup-unattended-upgrades.sh
    setup-logrotate.sh
  firewall/
    setup-iptables.sh     # Accepte SSH_PORT= et SSH_EXTRA_PORT= en variables
  ssh/
    setup-ports.sh        # Accepte SSH_EXTRA_PORT= (convention: 220XX)
  ssh-2fa/
    setup.sh              # PAM google-authenticator, nullok actif par défaut
    init-user.sh          # À lancer par l'utilisateur cible (pas root)

templates/<service>/      # Templates copiés vers /opt/<service>/ par install.sh
  compose.yaml
  nginx/nginx.conf        # Si l'app a besoin de nginx
  env.example             # Copié en .env (non commité)

secrets/                  # *.enc.yaml (SOPS) peuvent être commités, .env jamais
```

---

## Conventions de nommage

- **Noms de conteneurs** : `kernet-<service>` pour les services infra (traefik, crowdsec, watchtower), `<service>-app`, `<service>-nginx`, `<service>-db` pour les apps encapsulées
- **Noms de réseaux Docker** : `<service>_internal` (créés par compose), `proxy` (externe, manuel)
- **Volumes** : bind mounts vers `/opt/<service>/data`, `/opt/<service>/db`, `/opt/<service>/nginx`
- **Labels Traefik** : toujours inclure `traefik.docker.network=proxy` quand le conteneur est sur plusieurs réseaux
- **Middlewares publics** : ajouter `security-headers@file,rate-limit-public@file` sur toutes les routes publiques

---

## Variables d'environnement — points d'attention

- Dans un fichier `.env`, les `$` dans les hashes bcrypt (BasicAuth) doivent être **doublés** : `$$2y$$...`
- `LETSENCRYPT_EMAIL` doit être dans l'**environnement du conteneur Traefik** (pas seulement dans `.env`) pour que `traefik.yml` puisse le lire
- Les `.env` sont en permissions `0600` (copiés ainsi par `install.sh`)

---

## Bugs connus corrigés (historique)

| Bug | Description | Fix appliqué |
|-----|-------------|-------------|
| PAM `user=root` | Tous les users SSH utilisaient le secret OTP de root | Retiré : chaque user lit son propre `~/.google_authenticator` |
| Double `labels:` Vaultwarden | Deux blocs `labels:` sur le même service = le second écrase le premier en YAML | Fusionné en un seul bloc |
| WebSocket Vaultwarden port 3012 | Déprécié depuis v1.29, WebSocket intégré au port principal | nginx routé vers port 8080, upstream `vaultwarden_ws` supprimé |
| BasicAuth Traefik dans `middlewares.yml` | Le file provider ne substitue pas les env vars | Middleware déplacé en label Docker (`@docker`), env var ajoutée au conteneur |

## Ce qui n'est PAS dans ce repo (volontairement)

- **Pas de SMTP configuré** : Matomo, Vaultwarden et Wiki.js ont des variables SMTP mais non configurées (à ajouter selon le prestataire)
- **Pas de backup PostgreSQL automatique** : snapshots OVH utilisés pour l'instant
- **Pas de workflow SOPS finalisé** : structure prête (`secrets/`, `.sops.yaml`), à compléter avec une clé age réelle
- **Pas de Netdata/Prometheus** : Uptime Kuma couvre le monitoring de base

---

## Commandes utiles (rappel)

```bash
# Déploiement complet
sudo bash ops/system/install-docker.sh
sudo bash ops/install.sh
sudo SSH_EXTRA_PORT=22047 bash ops/ssh/setup-ports.sh
sudo SSH_PORT=22 SSH_EXTRA_PORT=22047 bash ops/firewall/setup-iptables.sh
sudo bash ops/deploy.sh

# Vérifier les règles firewall
sudo iptables -n -L --line-numbers

# Décisions CrowdSec
docker exec kernet-crowdsec cscli decisions list

# Regénérer le hash BasicAuth
htpasswd -nbB admin 'motdepasse'
# Dans .env, doubler les $ : $2y$ → $$2y$$

# Générer un token fort (Vaultwarden admin)
openssl rand -base64 48
```

---

## Éditeur utilisé

**vim** (pas nano). Toutes les commandes d'édition dans la doc utilisent `vim`.

## Comment ajouter une nouvelle application

1. Ajouter `ENABLE_<APP>=false` dans `ops/config.sh`
2. Créer `templates/<app>/compose.yaml` en suivant le pattern existant :
   - Réseau interne dédié (`<app>_internal`, `internal: true`)
   - PostgreSQL si besoin (avec healthcheck)
   - nginx si PHP-FPM ou besoin d'un proxy interne
   - Réseau `proxy` (external) uniquement sur le conteneur exposé
   - Labels Traefik : `traefik.enable`, `traefik.docker.network=proxy`, router, tls, certresolver, middlewares
   - Label Watchtower : `com.centurylinklabs.watchtower.enable=true` sur tous les conteneurs
2. Créer `templates/<app>/env.example`
3. Créer `templates/<app>/env.example`
4. Ajouter les blocs `if [[ "${ENABLE_APP}" == "true" ]]; then ... fi` dans `ops/install.sh` et `ops/deploy.sh`

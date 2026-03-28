# Déploiement sur un nouveau VPS OVH

Guide pas-à-pas pour partir d'un VPS Ubuntu vierge et arriver à une infra
complète et fonctionnelle.

---

## Prérequis

- VPS OVH avec **Ubuntu** fraîchement installé
- Accès SSH root ou sudo
- Ports **80** et **443** ouverts (vérifier dans l'espace client OVH)
- Un domaine avec des sous-domaines qui pointent vers l'IP du VPS (enregistrements DNS A)

---

## Étape 0 — Connexion SSH initiale

Depuis ton PC :

```bash
ssh root@<IP_DU_VPS>
```

---

## Étape 1 — Installer Git

```bash
apt-get update -y
apt-get install -y git
```

---

## Étape 2 — Cloner le repo

```bash
git clone https://github.com/MythaelX/KerNet /opt/kernet
cd /opt/kernet
```

---

## Étape 3 — Choisir ses services

Ouvre le fichier de configuration et active/désactive les services que tu veux :

```bash
vim ops/config.sh
```

```bash
# Exemple : activer Wiki.js, désactiver Matomo
ENABLE_MATOMO=false
ENABLE_WIKIJS=true
```

---

## Étape 4 — Installer Docker

```bash
sudo bash ops/system/install-docker.sh
```

Vérifie :
```bash
docker --version
docker compose version
```

---

## Étape 5 — Préparer le système

Remplace `Europe/Paris` par ton fuseau si besoin. Le swap est mis à 2 Go par défaut.

```bash
sudo TIMEZONE=Europe/Paris SWAP_SIZE_MB=2048 bash ops/system/setup-system.sh
```

Ce script installe :
- **Swap** (évite les OOM kills sur PostgreSQL)
- **rsyslog** (nécessaire pour `/var/log/auth.log` → CrowdSec SSH)
- **vim** comme éditeur par défaut
- Configure la **timezone** et active **NTP**

---

## Étape 6 — Initialiser les dossiers et templates

```bash
sudo bash ops/install.sh
```

Les dossiers `/opt/traefik`, `/opt/matomo`, etc. sont créés et les templates
sont copiés dedans. Idempotent : tu peux relancer sans risque.

---

## Étape 7 — Configurer les .env

Chaque service a son propre `.env` dans `/opt/<service>/`. Édite ceux qui
correspondent aux services activés dans `config.sh`.

### Traefik (obligatoire)

```bash
vim /opt/traefik/.env
```

| Variable | Valeur attendue |
|----------|----------------|
| `LETSENCRYPT_EMAIL` | Ton email admin |
| `TRAEFIK_DASHBOARD_HOST` | `traefik.ton-domaine.tld` |
| `TRAEFIK_DASHBOARD_BASIC_AUTH` | Hash bcrypt (voir ci-dessous) |

**Générer le hash BasicAuth :**
```bash
# Installe htpasswd si absent
apt-get install -y apache2-utils
htpasswd -nbB admin 'ton_mot_de_passe'
# → copie le résultat, remplace chaque $ par $$ dans le .env
# Exemple : admin:$2y$... devient admin:$$2y$$...
```

### Matomo (si activé)

```bash
vim /opt/matomo/.env
```

```
MATOMO_HOST=matomo.ton-domaine.tld
MATOMO_DB_NAME=matomo
MATOMO_DB_USER=matomo
MATOMO_DB_PASSWORD=un_mot_de_passe_fort
```

### Vaultwarden (si activé)

```bash
vim /opt/vaultwarden/.env
```

```
VAULTWARDEN_HOST=vault.ton-domaine.tld
VAULTWARDEN_SIGNUPS_ALLOWED=false
VAULTWARDEN_ADMIN_TOKEN=   # générer : openssl rand -base64 48
VW_DB_NAME=vaultwarden
VW_DB_USER=vaultwarden
VW_DB_PASSWORD=un_mot_de_passe_fort
```

> **Note :** mets `VAULTWARDEN_SIGNUPS_ALLOWED=true` pour créer ton compte,
> puis repasse à `false` et relance : `docker compose -f /opt/vaultwarden/compose.yaml --env-file /opt/vaultwarden/.env up -d`

### Uptime Kuma (si activé)

```bash
vim /opt/uptime-kuma/.env
```

```
UPTIME_KUMA_HOST=status.ton-domaine.tld
```

### Wiki.js (si activé)

```bash
vim /opt/wikijs/.env
```

```
WIKIJS_HOST=wiki.ton-domaine.tld
WIKIJS_DB_NAME=wikijs
WIKIJS_DB_USER=wikijs
WIKIJS_DB_PASSWORD=un_mot_de_passe_fort
```

### CrowdSec

```bash
vim /opt/crowdsec/.env
```

```
CROWDSEC_COLLECTIONS=crowdsecurity/traefik crowdsecurity/sshd
CROWDSEC_BOUNCER_KEY=   # laisse vide pour l'instant, on le génère après
```

---

## Étape 8 — Mises à jour automatiques + logs

```bash
sudo bash ops/system/setup-unattended-upgrades.sh
sudo bash ops/system/setup-logrotate.sh
```

---

## Étape 9 — Port SSH secondaire

La convention est `220XX` où `XX` sont les derniers chiffres de l'IP du VPS.

```bash
# Exemple : IP x.x.x.47 → port 22047
sudo SSH_EXTRA_PORT=22047 bash ops/ssh/setup-ports.sh
```

**Ouvre un second terminal et teste AVANT de continuer :**
```bash
ssh -p 22047 root@<IP_DU_VPS>
```

---

## Étape 10 — Pare-feu iptables

```bash
# Remplace 22047 par ton port secondaire
sudo SSH_PORT=22 SSH_EXTRA_PORT=22047 bash ops/firewall/setup-iptables.sh
```

Vérifie les règles actives :
```bash
iptables -n -L --line-numbers
```

---

## Étape 11 — SSH + 2FA Google Authenticator

```bash
# Activer le module PAM (en root, une seule fois)
sudo bash ops/ssh-2fa/setup.sh

# Pour chaque utilisateur qui doit se connecter
sudo -u <user> bash ops/ssh-2fa/init-user.sh
```

Scanne le QR code avec l'app **Google Authenticator** sur ton téléphone.
Teste la connexion dans un second terminal avant de fermer la session.

> Une fois **tous** les utilisateurs initialisés, renforce le 2FA :
> ```bash
> vim /etc/pam.d/sshd
> # → supprime "nullok" sur la ligne pam_google_authenticator.so
> systemctl reload ssh
> ```

---

## Étape 12 — Déployer les stacks

```bash
sudo bash ops/deploy.sh
```

Vérifie que tout tourne :
```bash
docker ps
```

---

## Étape 13 — Activer le bouncer CrowdSec

C'est la seule étape qui ne peut pas être automatisée (la clé n'existe
qu'après le premier démarrage de CrowdSec).

```bash
# 1. Générer la clé
docker exec kernet-crowdsec cscli bouncers add iptables-bouncer
# → note la clé affichée

# 2. L'ajouter dans le .env
vim /opt/crowdsec/.env
# CROWDSEC_BOUNCER_KEY=la_cle_generee

# 3. Démarrer le bouncer
docker compose -f /opt/crowdsec/compose.yaml --env-file /opt/crowdsec/.env up -d
```

Vérifie que le bouncer est actif :
```bash
docker exec kernet-crowdsec cscli bouncers list
```

---

## Étape 14 — Fermer le port 22 (après validation du port secondaire)

Une fois que tu es certain que le port secondaire fonctionne :

```bash
# 1. Retirer Port 22 de la config sshd
vim /etc/ssh/sshd_config.d/50-kernet-ports.conf
# → supprime ou commente la ligne "Port 22"
systemctl reload ssh

# 2. Supprimer la règle firewall
iptables -D INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m limit --limit 6/min --limit-burst 10 -j ACCEPT
ip6tables -D INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m limit --limit 6/min --limit-burst 10 -j ACCEPT
netfilter-persistent save
```

---

## Résumé — ordre des commandes

```bash
# Connexion
ssh root@<IP>

# Prérequis
apt-get update -y && apt-get install -y git
git clone https://github.com/MythaelX/KerNet /opt/kernet
cd /opt/kernet

# Config
vim ops/config.sh

# Système
sudo bash ops/system/install-docker.sh
sudo TIMEZONE=Europe/Paris SWAP_SIZE_MB=2048 bash ops/system/setup-system.sh
sudo bash ops/install.sh

# .env (un par service activé)
vim /opt/traefik/.env
vim /opt/matomo/.env        # si activé
vim /opt/vaultwarden/.env   # si activé
vim /opt/crowdsec/.env

# Sécurité système
sudo bash ops/system/setup-unattended-upgrades.sh
sudo bash ops/system/setup-logrotate.sh

# SSH
sudo SSH_EXTRA_PORT=220XX bash ops/ssh/setup-ports.sh
# → tester dans un second terminal
sudo SSH_PORT=22 SSH_EXTRA_PORT=220XX bash ops/firewall/setup-iptables.sh
sudo bash ops/ssh-2fa/setup.sh
sudo -u <user> bash ops/ssh-2fa/init-user.sh

# Déploiement
sudo bash ops/deploy.sh

# CrowdSec bouncer (post-démarrage)
docker exec kernet-crowdsec cscli bouncers add iptables-bouncer
vim /opt/crowdsec/.env   # ajouter CROWDSEC_BOUNCER_KEY
docker compose -f /opt/crowdsec/compose.yaml --env-file /opt/crowdsec/.env up -d
```

---

## Dépannage rapide

### Traefik ne génère pas de certificat Let's Encrypt

```bash
# Vérifier que les ports 80/443 sont ouverts
curl -I http://traefik.ton-domaine.tld
# Vérifier acme.json
cat /opt/traefik/data/acme.json | python3 -m json.tool | grep -A2 '"status"'
# Logs Traefik
docker logs kernet-traefik --tail 50
```

### Un conteneur ne démarre pas

```bash
docker logs <nom-conteneur> --tail 50
docker inspect <nom-conteneur> | python3 -m json.tool | grep -A5 '"State"'
```

### CrowdSec bloque une IP légitime

```bash
docker exec kernet-crowdsec cscli decisions list
docker exec kernet-crowdsec cscli decisions delete --ip <IP>
```

### Mettre à jour manuellement une stack

```bash
docker compose -f /opt/matomo/compose.yaml --env-file /opt/matomo/.env pull
docker compose -f /opt/matomo/compose.yaml --env-file /opt/matomo/.env up -d
```

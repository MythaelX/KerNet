# Secrets

Ce dossier est prévu pour les secrets chiffrés via **SOPS + age**.

## Workflow (à mettre en place quand tu passeras à SOPS)

### 1. Générer une clé age

```bash
age-keygen -o ~/.config/sops/age/keys.txt
# Noter la clé publique affichée (age1...)
```

### 2. Renseigner la clé publique dans `.sops.yaml`

Remplace `age: []` par `age: ["age1...ta_cle_publique..."]` dans `.sops.yaml`.

### 3. Créer un fichier de secrets chiffré

```bash
# Exemple pour Traefik
sops secrets/traefik.enc.yaml
```

Format YAML attendu :

```yaml
TRAEFIK_DASHBOARD_BASIC_AUTH: "admin:$2y$..."
LETSENCRYPT_EMAIL: "admin@example.tld"
TRAEFIK_DASHBOARD_HOST: "traefik.example.tld"
```

### 4. Déchiffrer et injecter les .env (à scripter)

```bash
sops -d secrets/traefik.enc.yaml | \
  python3 -c "import sys,yaml; d=yaml.safe_load(sys.stdin); [print(f'{k}={v}') for k,v in d.items()]" \
  > /opt/traefik/.env
chmod 600 /opt/traefik/.env
```

## Fichiers attendus (quand SOPS sera configuré)

| Fichier | Contenu |
|---------|---------|
| `secrets/traefik.enc.yaml` | Domaine dashboard, email, hash BasicAuth |
| `secrets/matomo.enc.yaml` | Domaine, mdp DB |
| `secrets/vaultwarden.enc.yaml` | Domaine, admin token, mdp DB |
| `secrets/crowdsec.enc.yaml` | Clé bouncer |
| `secrets/uptime-kuma.enc.yaml` | Domaine |

## Important

- Les fichiers `*.enc.yaml` (chiffrés) PEUVENT être commités.
- Les fichiers `.env` et tout fichier non chiffré NE DOIVENT PAS être commités (voir `.gitignore`).

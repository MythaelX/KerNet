## Pare-feu iptables

### Politique
- **INPUT**: DROP par défaut
- **FORWARD**: DROP par défaut
- **OUTPUT**: ACCEPT (le VPS peut sortir librement)

### Ports ouverts
| Port | Protocole | Usage |
|------|-----------|-------|
| 22 (configurable via `SSH_PORT`) | TCP | SSH principal (à fermer manuellement après migration) |
| 220XX (via `SSH_EXTRA_PORT`) | TCP | SSH secondaire (derniers chiffres de l'IP, ex: 22047) |
| 80 | TCP | HTTP → Traefik (redirect HTTPS) |
| 443 | TCP | HTTPS → Traefik |

### Protections incluses
- **SYN flood**: limite à 20 SYN/s
- **ICMP**: limité à 5 ping/s
- **DOCKER-USER**: empêche l'accès direct aux ports des conteneurs depuis l'extérieur (Docker bypass)
- **IPv6**: mêmes règles que IPv4

### Ordre de déploiement recommandé

1. Appliquer le firewall (les deux ports SSH ouverts) :

```bash
# Remplace 22047 par 220 + les derniers chiffres de ton IP
sudo SSH_PORT=22 SSH_EXTRA_PORT=22047 bash ops/firewall/setup-iptables.sh
```

2. Configurer sshd pour écouter sur les deux ports :

```bash
sudo SSH_EXTRA_PORT=22047 bash ops/ssh/setup-ports.sh
```

3. **Tester le port secondaire dans un nouveau terminal avant de continuer.**

4. Démarrer les stacks Docker (les règles DOCKER-USER s'intègrent automatiquement).

5. Démarrer CrowdSec, générer la clé bouncer:

```bash
docker exec kernet-crowdsec cscli bouncers add iptables-bouncer
```

6. Copier la clé dans `/opt/crowdsec/.env` (`CROWDSEC_BOUNCER_KEY`), puis:

```bash
docker compose -f /opt/crowdsec/compose.yaml --env-file /opt/crowdsec/.env up -d
```

CrowdSec écrira ensuite dynamiquement ses propres règles iptables via le bouncer.

### Vérifier les règles actives

```bash
sudo iptables -n -L --line-numbers
sudo ip6tables -n -L --line-numbers
```

### Supprimer les IPs bloquées par CrowdSec

```bash
docker exec kernet-crowdsec cscli decisions list
docker exec kernet-crowdsec cscli decisions delete --ip <IP>
```

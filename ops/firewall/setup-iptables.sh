#!/usr/bin/env bash
# Durcissement pare-feu iptables pour VPS OVH Ubuntu
# Politique : DROP par défaut, autorise uniquement ce qui est explicitement ouvert.
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Ce script doit être exécuté en root (sudo)." >&2
  exit 1
fi

SSH_PORT="${SSH_PORT:-22}"
# Port secondaire optionnel (convention: 220XX, derniers chiffres de l'IP)
SSH_EXTRA_PORT="${SSH_EXTRA_PORT:-}"

echo "[firewall] Installation de iptables-persistent..."
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables iptables-persistent ipset

# ---------------------------------------------------------------------------
# ANTI-LOCKOUT : vérification que la session SSH actuelle sera conservée
# ---------------------------------------------------------------------------
if ! ss -tnp | grep -q ":${SSH_PORT}"; then
  echo "[firewall] AVERTISSEMENT: aucune connexion SSH détectée sur le port ${SSH_PORT}."
  echo "Vérifie SSH_PORT= avant de continuer."
fi

if [[ -n "$SSH_EXTRA_PORT" ]]; then
  echo "[firewall] Port SSH secondaire activé : ${SSH_EXTRA_PORT}"
fi

echo "[firewall] Application des règles IPv4..."

# ---- Vider les règles existantes ----
iptables -F
iptables -X
iptables -Z
iptables -t nat -F
iptables -t mangle -F

# ---- Politiques par défaut ----
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# ---- Loopback ----
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# ---- Connexions établies / relatives ----
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# ---- Protection SYN flood via chaîne dédiée ----
# IMPORTANT: on utilise une chaîne dédiée avec RETURN pour que les paquets
# acceptés retournent dans INPUT et continuent le traitement (règles de port).
# Une règle directe --syn ACCEPT dans INPUT bypasse toutes les règles suivantes.
iptables -N SYNFLOOD 2>/dev/null || iptables -F SYNFLOOD
iptables -A SYNFLOOD -m limit --limit 20/s --limit-burst 100 -j RETURN
iptables -A SYNFLOOD -j DROP
iptables -A INPUT -p tcp --syn -j SYNFLOOD

# ---- ICMP (ping) : limité ----
iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 5/s --limit-burst 10 -j ACCEPT

# ---- SSH ----
iptables -A INPUT -p tcp --dport "${SSH_PORT}" -m conntrack --ctstate NEW -m limit --limit 6/min --limit-burst 10 -j ACCEPT
if [[ -n "$SSH_EXTRA_PORT" ]]; then
  iptables -A INPUT -p tcp --dport "${SSH_EXTRA_PORT}" -m conntrack --ctstate NEW -m limit --limit 6/min --limit-burst 10 -j ACCEPT
fi

# ---- HTTP / HTTPS (Traefik) ----
iptables -A INPUT -p tcp --dport 80  -m conntrack --ctstate NEW -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW -j ACCEPT

# ---- CrowdSec LAPI (local uniquement, déjà filtré par bind 127.0.0.1) ----
iptables -A INPUT -i lo -p tcp --dport 8080 -j ACCEPT

# ---- DROP silencieux pour le reste ----
iptables -A INPUT -j DROP

# ---------------------------------------------------------------------------
# DOCKER-USER : laisser Docker gérer l'isolation des conteneurs
# ---------------------------------------------------------------------------
# NE PAS bloquer depuis eth0 dans DOCKER-USER :
# le trafic vers les ports publiés (80/443 de Traefik) passe par PREROUTING
# (DNAT) puis FORWARD. Un DROP sur -i eth0 rendrait Traefik inaccessible.
# Docker assure déjà que seuls les ports déclarés avec "ports:" sont joignables.
if ! iptables -n -L DOCKER-USER >/dev/null 2>&1; then
  iptables -N DOCKER-USER
fi
iptables -F DOCKER-USER
iptables -A DOCKER-USER -j RETURN

# ---------------------------------------------------------------------------
# IPv6
# ---------------------------------------------------------------------------
echo "[firewall] Application des règles IPv6..."
ip6tables -F
ip6tables -X
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT

ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp -j ACCEPT

ip6tables -N SYNFLOOD6 2>/dev/null || ip6tables -F SYNFLOOD6
ip6tables -A SYNFLOOD6 -m limit --limit 20/s --limit-burst 100 -j RETURN
ip6tables -A SYNFLOOD6 -j DROP
ip6tables -A INPUT -p tcp --syn -j SYNFLOOD6

ip6tables -A INPUT -p tcp --dport "${SSH_PORT}" -m conntrack --ctstate NEW -m limit --limit 6/min --limit-burst 10 -j ACCEPT
if [[ -n "$SSH_EXTRA_PORT" ]]; then
  ip6tables -A INPUT -p tcp --dport "${SSH_EXTRA_PORT}" -m conntrack --ctstate NEW -m limit --limit 6/min --limit-burst 10 -j ACCEPT
fi
ip6tables -A INPUT -p tcp --dport 80  -m conntrack --ctstate NEW -j ACCEPT
ip6tables -A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW -j ACCEPT
ip6tables -A INPUT -j DROP

# ---------------------------------------------------------------------------
# Persistance
# ---------------------------------------------------------------------------
echo "[firewall] Sauvegarde des règles (iptables-persistent)..."
netfilter-persistent save

echo ""
echo "[firewall] Règles appliquées et sauvegardées."
echo ""
echo "Règles IPv4 actives:"
iptables -n -L --line-numbers
echo ""
if [[ -n "$SSH_EXTRA_PORT" ]]; then
  echo "Ports SSH ouverts : ${SSH_PORT} (principal) + ${SSH_EXTRA_PORT} (secondaire)"
  echo "N'oublie pas de configurer sshd : sudo SSH_EXTRA_PORT=${SSH_EXTRA_PORT} bash ops/ssh/setup-ports.sh"
fi
echo ""
echo "Rappel: après avoir démarré CrowdSec, génère la clé bouncer:"
echo "  docker exec kernet-crowdsec cscli bouncers add iptables-bouncer"

## Objectif
Activer l’authentification SSH avec OTP (Google Authenticator) pour tous les utilisateurs, en acceptant :
- **clé SSH + OTP**
- **ou** **mot de passe + OTP**

### Attention (risque de lockout)
L’activation de 2FA sur SSH peut te **verrouiller** hors du serveur si :
- tu perds la session root actuelle
- tu actives l’exigence OTP avant d’avoir initialisé chaque utilisateur

Fais-le dans une session persistante (tmux) et garde une console OVH/KVM à portée.

## Étapes
1) Appliquer la configuration SSH + PAM :

```bash
sudo bash ops/ssh-2fa/setup.sh
```

2) Pour chaque utilisateur qui doit se connecter, générer le secret OTP :

```bash
sudo -u <user> bash ops/ssh-2fa/init-user.sh
```

3) Tester une nouvelle connexion SSH dans un second terminal.

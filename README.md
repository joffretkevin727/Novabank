# README — DÉPLOIEMENT ET ADMINISTRATION NOVABANK (E0, E1, DÉBUT E2)

## E0 — LA VM, SSH ET GIT

### 1. CONFIGURATION RÉSEAU (VIRTUALBOX)

Dans les paramètres de la machine virtuelle éteinte :

- **Carte 1 :** attachée au mode NAT (accès Internet pour les paquets).
- **Carte 2 :** attachée au mode Réseau privé hôte (Host-only) pour communiquer avec le PC hôte.

### 2. NOM D'HÔTE ET IP FIXE (NETPLAN)

Sur la VM Ubuntu :

#### a) Définir le nom d'hôte

```bash
sudo hostnamectl set-hostname dbpostgre
```

#### b) Repérer le nom de la seconde interface réseau sans IP

```bash
ip -br a
```

#### c) Configurer l'adresse IP fixe via Netplan (utiliser des espaces, pas de tabulations)

```bash
sudo nano /etc/netplan/01-netcfg.yaml
```

Contenu du fichier YAML :

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s3:
      dhcp4: true
    enp0s8:
      addresses:
        - 192.168.56.10/24
```

#### d) Appliquer les réglages

```bash
sudo netplan apply
```

### 3. AUTHENTIFICATION SSH PAR CLÉ

Depuis le terminal PowerShell sur Windows :

#### a) Générer la paire de clés Ed25519

```powershell
ssh-keygen -t ed25519
```

#### b) Envoyer la clé publique sur la VM

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh kevin@192.168.56.10 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

#### c) Tester la connexion sans mot de passe

```powershell
ssh kevin@192.168.56.10
```

### 4. CONFIGURATION DU DÉPÔT GIT

Dans la session SSH sur la VM :

```bash
git config --global user.name "Kevin"
git config --global user.email "kevin@exemple.com"

mkdir -p ~/novabank && cd ~/novabank

git init
```

Créer le fichier `.gitattributes` (pour forcer les fins de ligne Unix LF) :

```bash
cat << 'EOF' > .gitattributes
* text=auto
*.sh text eol=lf
EOF
```

Créer le fichier `.gitignore` :

```bash
cat << 'EOF' > .gitignore
*.key
*.pub
*.dump
*.sql.gz
*.log
.env
EOF
```

#### Premier commit

```bash
git add .gitattributes .gitignore

git commit -m "chore: configuration initiale git, gitignore et gitattributes"
```

---

## E1 — LE SERVEUR POSTGRESQL 18 & SÉCURISATION UFW

### 1. SCRIPT D'INSTALLATION : 

`~/novabank/install_server.sh`

### 2. EXÉCUTION ET VALIDATION

```bash
chmod +x ~/novabank/install_server.sh

sudo ~/novabank/install_server.sh
```

#### Commandes de vérification

**Vérifier l'état du cluster :**

```bash
pg_lsclusters
```

**Vérifier l'écoute réseau :**

```bash
sudo -u postgres psql -c "SHOW listen_addresses;"
```

**Vérifier l'absence d'erreurs dans `pg_hba.conf` :**

```bash
sudo -u postgres psql -c "SELECT line_number, user_name, auth_method, error FROM pg_hba_file_rules;"
```

---

## E2 — LES TABLES ET LES DONNÉES (EN COURS)

### 1. INITIALISATION DU RÔLE ET DE LA BASE

Exécuter sur la VM :

```bash
sudo -u postgres psql -c "CREATE ROLE bank_owner WITH LOGIN CREATEDB;"

sudo -u postgres psql -c "\password bank_owner"

sudo -u postgres psql -c "CREATE DATABASE bankdb OWNER bank_owner;"

sudo -u postgres psql -d bankdb -c "CREATE SCHEMA core AUTHORIZATION bank_owner;"
```

### 2. SCRIPT DE CRÉATION ET D'INJECTION : 

`~/novabank/init_db.sql`

### 3. EXÉCUTION VIA REDIRECTION DE FLUX

```bash
sudo -u postgres psql < ~/novabank/init_db.sql
```

### 4. CONTRÔLES DE VALIDATION

#### Nombre d'écritures (attendu : 1000000)

```bash
sudo -u postgres psql -d bankdb -c "SELECT count(*) FROM core.ecritures;"
```

#### Cohérence des soldes et absence de solde négatif (attendu : 0 ligne)

```bash
sudo -u postgres psql -d bankdb -c "SELECT c.compte_id, c.solde, e.balance_after FROM core.comptes c JOIN (SELECT DISTINCT ON (compte_id) compte_id, balance_after FROM core.ecritures ORDER BY compte_id, date_operation DESC) e ON c.compte_id = e.compte_id WHERE c.solde != e.balance_after OR c.solde < 0;"
```

---

================================================================================


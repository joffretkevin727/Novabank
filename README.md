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

## E3 — SÉCURITÉ ET PRIVILÈGES D'ACCÈS

### 1. PRINCIPE APPLIQUÉ

Mise en œuvre du principe de moindre privilège et de la « règle des trois portes » :

1. Droit de connexion au niveau base (`CONNECT`).
2. Droit de traversée du schéma (`USAGE`).
3. Droit granulaire sur les objets (`SELECT`, `INSERT`, `UPDATE`).

Révocation préalable de tous les accès résiduels hérités du pseudo-rôle `PUBLIC`.

### 2. SCRIPT DE CONFIGURATION : `~/novabank/sql/e3_01_privileges.sql`

Structure mise en place :

- **Groupes NOLOGIN :** `app_grp`, `analystes`, `support`, `auditeurs`.
- **Utilisateurs LOGIN :** `app_user`, `analyste_user`, `support_user`, `auditeur_user`.
- **Garde-fous :** `statement_timeout` configuré pour les profils de consultation.
- **Persistance :** `ALTER DEFAULT PRIVILEGES` appliqués pour garantir les droits sur les tables futures.

### 3. SCRIPT DE VÉRIFICATION : `~/novabank/sql/e3_02_privileges_tests.sql`

### 4. EXÉCUTION ET VALIDATION

**Commandes :**

```bash
sudo -u postgres psql -d bankdb -f ~/novabank/sql/e3_01_privileges.sql

sudo -u postgres psql -d bankdb -f ~/novabank/sql/e3_02_privileges_tests.sql
```

**Matrice de contrôle des droits :**

```bash
sudo -u postgres psql -d bankdb -c "SELECT grantee, table_schema, table_name, privilege_type FROM information_schema.role_table_grants WHERE table_schema = 'core' ORDER BY grantee, table_name, privilege_type;"
```

---

## E4 — LES VUES (SÉCURITÉ, CONTRÔLE ET PERFORMANCE)

### 1. PRINCIPE ET OBJECTIFS

Exposer les données sous contrôle strict :

- Masquer les données sensibles pour le support sans fuite via l'optimiseur (`security_barrier`).
- Permettre la mise à jour via vue tout en verrouillant le périmètre métier (`WITH LOCAL CHECK OPTION`).
- Pré-agréger des métriques de reporting rafraîchissables à chaud sans bloquer les lectures (`REFRESH MATERIALIZED VIEW CONCURRENTLY`).

### 2. SCRIPT DE CRÉATION : `~/novabank/sql/e4_01_views_creation.sql`

**Objets créés :**

- **`core.v_clients_support` :** vue dotée de `security_barrier = true`. Les champs `nom` et `prenom` sont masqués (initiale + `***`), `date_naissance` est tronquée à l'année. Droit `SELECT` accordé au groupe `support`.
- **`core.v_comptes_courants` :** vue filtrant sur `type = 'courant'` avec clause `WITH LOCAL CHECK OPTION`. Droit de modification ciblé `UPDATE(solde, type)` accordé au groupe `app_grp`.
- **`core.mv_synthese_clients` :** vue matérialisée calculant le nombre de comptes et l'encours total par client. Indexée de manière unique sur `client_id` (`idx_mv_synthese_clients_id`). Droit `SELECT` accordé aux `analystes`.

### 3. SCRIPT DE VALIDATION : `~/novabank/sql/e4_02_views_tests.sql`

### 4. EXÉCUTION ET VALIDATION

**Commandes :**

```bash
sudo -u postgres psql -d bankdb -f ~/novabank/sql/e4_01_views_creation.sql

sudo -u postgres psql -d bankdb -f ~/novabank/sql/e4_02_views_tests.sql
```

#### Contrôles de validation

**Validation du masquage support :**

```bash
sudo -u postgres psql -d bankdb -c "SET ROLE support_user; SELECT * FROM core.v_clients_support LIMIT 3; RESET ROLE;"
```

Résultat attendu : prénoms et noms masqués sous forme `P***`, `N***`.

**Validation du rejet CHECK OPTION :**

```bash
sudo -u postgres psql -d bankdb -c "SET ROLE app_user; UPDATE core.v_comptes_courants SET type = 'epargne'::core.type_compte WHERE compte_id = (SELECT compte_id FROM core.v_comptes_courants LIMIT 1); RESET ROLE;"
```

Résultat attendu :

```text
ERROR: new row violates check option for view "v_comptes_courants"
```

**Validation du rafraîchissement concurrentiel :**

```bash
sudo -u postgres psql -d bankdb -c "REFRESH MATERIALIZED VIEW CONCURRENTLY core.mv_synthese_clients;"

sudo -u postgres psql -d bankdb -c "SET ROLE analyste_user; SELECT * FROM core.mv_synthese_clients LIMIT 3; RESET ROLE;"
```

Résultat attendu : rafraîchissement sans verrouillage exclusif sur les lectures.

---



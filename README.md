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

### 1. SCRIPT D'INSTALLATION : `~/novabank/install_server.sh`

Créer le fichier :

```bash
cat << 'EOF' > ~/novabank/install_server.sh
#!/usr/bin/env bash

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "Erreur : ce script doit être exécuté en root (sudo)." >&2
    exit 1
fi

echo "=== [1/5] Installation des paquets ==="

apt-get update -y
apt-get install -y postgresql postgresql-client ufw

PG_DIR="/etc/postgresql/18/main"
CONF_D="${PG_DIR}/conf.d"

mkdir -p "${CONF_D}"

echo "=== [2/5] Configuration conf.d ==="

cat << 'CONF' > "${CONF_D}/99-novabank.conf"
listen_addresses = '*'
password_encryption = 'scram-sha-256'
log_connections = on
log_statement = 'all'
CONF

chown -R postgres:postgres "${CONF_D}"
chmod 644 "${CONF_D}/99-novabank.conf"

echo "=== [3/5] Configuration pg_hba.conf ==="

cat << 'HBA' > "${PG_DIR}/pg_hba.conf"
local   all             postgres                                peer
local   all             all                                     scram-sha-256
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
host    all             +analystes      192.168.56.0/24         scram-sha-256
host    all             +support        192.168.56.0/24         scram-sha-256
host    all             +auditeurs      192.168.56.0/24         scram-sha-256
host    all             all             0.0.0.0/0               reject
host    all             all             ::/0                    reject
HBA

chown postgres:postgres "${PG_DIR}/pg_hba.conf"
chmod 640 "${PG_DIR}/pg_hba.conf"

echo "=== [4/5] Redémarrage de PostgreSQL ==="

systemctl restart postgresql
systemctl enable postgresql

echo "=== [5/5] Configuration UFW ==="

ufw allow OpenSSH
ufw allow from 192.168.56.0/24 to any port 5432 proto tcp
ufw --force enable

echo "=== Déploiement serveur terminé avec succès ==="
EOF
```

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

### 2. SCRIPT DE CRÉATION ET D'INJECTION : `~/novabank/init_e2.sql`

Créer le fichier :

```bash
cat << 'EOF' > ~/novabank/init_e2.sql
\c bankdb

SET search_path TO core, public;

DROP TABLE IF EXISTS core.ecritures CASCADE;
DROP TABLE IF EXISTS core.virements CASCADE;
DROP TABLE IF EXISTS core.comptes CASCADE;
DROP TABLE IF EXISTS core.clients CASCADE;

DROP TYPE IF EXISTS core.type_ecriture CASCADE;
DROP TYPE IF EXISTS core.type_compte CASCADE;
DROP TYPE IF EXISTS core.statut_client CASCADE;

CREATE TYPE core.statut_client AS ENUM ('actif', 'suspendu', 'cloture');
CREATE TYPE core.type_compte AS ENUM ('courant', 'epargne');
CREATE TYPE core.type_ecriture AS ENUM ('depot', 'retrait', 'virement');

CREATE TABLE core.clients (
    client_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom text NOT NULL,
    prenom text NOT NULL,
    date_naissance date NOT NULL,
    statut core.statut_client NOT NULL DEFAULT 'actif',
    CONSTRAINT ck_clients_majeur CHECK (date_naissance <= CURRENT_DATE - INTERVAL '18 years')
);

CREATE TABLE core.comptes (
    compte_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_id bigint NOT NULL REFERENCES core.clients(client_id),
    type core.type_compte NOT NULL DEFAULT 'courant',
    solde numeric(14,2) NOT NULL DEFAULT 0.00,
    ouvert_le timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_comptes_solde_positif CHECK (solde >= 0)
);

CREATE TABLE core.virements (
    virement_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    compte_source_id bigint NOT NULL REFERENCES core.comptes(compte_id),
    compte_destination_id bigint NOT NULL REFERENCES core.comptes(compte_id),
    montant numeric(14,2) NOT NULL,
    execute_le timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_virements_comptes_distincts CHECK (compte_source_id != compte_destination_id),
    CONSTRAINT ck_virements_montant_positif CHECK (montant > 0)
);

CREATE TABLE core.ecritures (
    ecriture_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    compte_id bigint NOT NULL REFERENCES core.comptes(compte_id),
    virement_id bigint REFERENCES core.virements(virement_id),
    type core.type_ecriture NOT NULL,
    montant numeric(14,2) NOT NULL,
    balance_after numeric(14,2) NOT NULL,
    date_operation timestamptz NOT NULL,
    CONSTRAINT ck_ecritures_balance_positive CHECK (balance_after >= 0)
);

SELECT setseed(0.42);

INSERT INTO core.clients (nom, prenom, date_naissance)
SELECT
    'Nom_' || g,
    'Prenom_' || g,
    DATE '1980-01-01' + ((g % 10000) || ' days')::interval
FROM generate_series(1, 10000) g;

INSERT INTO core.comptes (client_id, type, solde, ouvert_le)
SELECT
    1 + (g % 10000),
    'courant'::core.type_compte,
    0.00,
    TIMESTAMPTZ '2026-01-01 08:00:00+00'
FROM generate_series(1, 20000) g;

CREATE TEMP TABLE tmp_brut (
    compte_id bigint,
    virement_id bigint,
    type core.type_ecriture,
    montant numeric(14,2),
    date_op timestamptz
);

INSERT INTO tmp_brut
SELECT
    g,
    NULL,
    'depot'::core.type_ecriture,
    10000.00,
    TIMESTAMPTZ '2026-01-01 09:00:00+00'
FROM generate_series(1, 20000) g;

WITH vir_gen AS (
    INSERT INTO core.virements (compte_source_id, compte_destination_id, montant, execute_le)
    SELECT
        1 + (g % 20000) AS src,
        1 + ((g + 3) % 20000) AS dst,
        (10 + (g % 50))::numeric(14,2) AS mnt,
        TIMESTAMPTZ '2026-01-02 00:00:00+00' + (g || ' seconds')::interval
    FROM generate_series(1, 490000) g
    RETURNING virement_id, compte_source_id, compte_destination_id, montant, execute_le
)
INSERT INTO tmp_brut (compte_id, virement_id, type, montant, date_op)
SELECT compte_source_id, virement_id, 'virement'::core.type_ecriture, -montant, execute_le
FROM vir_gen
UNION ALL
SELECT compte_destination_id, virement_id, 'virement'::core.type_ecriture, montant, execute_le
FROM vir_gen;

INSERT INTO core.ecritures (compte_id, virement_id, type, montant, balance_after, date_operation)
SELECT
    compte_id,
    virement_id,
    type,
    montant,
    sum(montant) OVER (PARTITION BY compte_id ORDER BY date_op, type) AS balance_after,
    date_op
FROM tmp_brut;

UPDATE core.comptes c
SET solde = sub.dernier_solde
FROM (
    SELECT DISTINCT ON (compte_id)
        compte_id,
        balance_after AS dernier_solde
    FROM core.ecritures
    ORDER BY compte_id, date_operation DESC
) sub
WHERE c.compte_id = sub.compte_id;

DROP TABLE tmp_brut;

ANALYZE core.ecritures;
ANALYZE core.comptes;
EOF
```

### 3. EXÉCUTION VIA REDIRECTION DE FLUX

```bash
sudo -u postgres psql < ~/novabank/init_e2.sql
```

### 4. CONTRÔLES DE VALIDATION E2

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


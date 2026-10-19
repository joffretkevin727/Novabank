
# NovaBank — Installation et administration PostgreSQL

## Sommaire

- [E0 — Préparation de l'environnement](#e0--préparation-de-lenvironnement)
- [E1 — Installation du serveur PostgreSQL](#e1--installation-du-serveur-postgresql)
- [E2 — Création de la base et des données](#e2--création-de-la-base-et-des-données)
- [E3 — Gestion des rôles et des privilèges](#e3--gestion-des-rôles-et-des-privilèges)
- [E4 — Vues et vues matérialisées](#e4--vues-et-vues-matérialisées)
- [E5 — Indexation et benchmarks](#e5--indexation-et-benchmarks)

---

# E0 — Préparation de l'environnement

## 1. Configuration de la machine virtuelle

La machine virtuelle Ubuntu est configurée avec VirtualBox et deux interfaces réseau :

- **NAT (`enp0s3`)** : accès à Internet.
- **Host-only (`enp0s8`)** : communication entre Windows et Ubuntu.

Le nom d'hôte de la machine est `dbpostgre`.

### Configuration réseau

Éditer le fichier Netplan :

```bash
sudo nano /etc/netplan/50-cloud-init.yaml
```

Exemple de configuration :

```yaml
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: true
    enp0s8:
      dhcp4: false
      addresses:
        - 192.168.56.10/24
```

Appliquer la configuration :

```bash
sudo netplan apply
```

Vérifier les interfaces :

```bash
ip addr
```

## 2. Connexion SSH depuis Windows

Depuis PowerShell, envoyer la clé publique SSH vers Ubuntu :

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh kevin@192.168.56.10 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

Se connecter à la machine virtuelle :

```powershell
ssh kevin@192.168.56.10
```

## 3. Configuration de Git

Configurer l'identité Git :

```bash
git config --global user.name "Votre Nom"
git config --global user.email "votre.email@example.com"
```

Créer le fichier `.gitattributes` :

```gitattributes
* text=auto
*.sh text eol=lf
*.sql text eol=lf
*.md text eol=lf
```

Créer le fichier `.gitignore` :

```gitignore
*.log
*.tmp
.env
.DS_Store
```

Initialiser le dépôt Git et créer le premier commit :

```bash
git init
git add .
git commit -m "Initialisation du projet NovaBank"
```

---

# E1 — Installation du serveur PostgreSQL

## 1. Exécution du script d'installation

Le script d'installation est situé dans :

```text
~/novabank/install_server.sh
```

Le rendre exécutable puis le lancer :

```bash
chmod +x ~/novabank/install_server.sh
sudo ~/novabank/install_server.sh
```

Le script prépare le serveur PostgreSQL et configure notamment son accès réseau et les règles de connexion.

## 2. Vérifications

Vérifier l'état du cluster PostgreSQL :

```bash
pg_lsclusters
```

Vérifier la configuration d'écoute :

```bash
sudo -u postgres psql -c "SHOW listen_addresses;"
```

Vérifier les règles d'authentification :

```bash
sudo -u postgres psql -c "SELECT * FROM pg_hba_file_rules;"
```

---

# E2 — Création de la base et des données

## 1. Création du rôle et de la base

Ouvrir une session PostgreSQL :

```bash
sudo -u postgres psql
```

Créer le rôle propriétaire :

```sql
CREATE ROLE bank_owner LOGIN CREATEDB;
```

Définir son mot de passe de manière interactive :

```text
\password bank_owner
```

Créer la base de données :

```sql
CREATE DATABASE bankdb OWNER bank_owner;
```

Quitter PostgreSQL :

```text
\q
```

## 2. Initialisation du schéma

Le script d'initialisation est situé dans :

```text
~/novabank/init_db.sql
```

L'exécuter sur la base `bankdb` :

```bash
sudo -u postgres psql -d bankdb -f ~/novabank/init_db.sql
```

Ce script initialise le schéma et les données du projet NovaBank.

## 3. Vérification des données

Se connecter à la base :

```bash
sudo -u postgres psql -d bankdb
```

Vérifier le nombre d'écritures :

```sql
SELECT COUNT(*) FROM core.ecritures;
```

Le jeu de données attendu contient environ **1 000 000 d'écritures**, selon le script d'initialisation utilisé.

Vérifier la cohérence des écritures :

```sql
SELECT
    COUNT(*) AS nombre_ecritures,
    COUNT(*) FILTER (WHERE montant IS NULL) AS montants_nuls
FROM core.ecritures;
```

Quitter :

```text
\q
```

---

# E3 — Gestion des rôles et des privilèges

## 1. Objectif

Mettre en place une gestion des accès selon le principe du moindre privilège.

Les groupes de rôles sont :

| Groupe | Fonction |
|---|---|
| `app_grp` | Application bancaire |
| `analystes` | Analyse et consultation des données |
| `support` | Assistance clientèle |
| `auditeurs` | Contrôle et audit |

Les utilisateurs associés sont :

| Utilisateur | Groupe |
|---|---|
| `app_user` | `app_grp` |
| `analyste_user` | `analystes` |
| `support_user` | `support` |
| `auditeur_user` | `auditeurs` |

## 2. Scripts SQL

Les scripts de cette étape se trouvent dans :

```text
~/novabank/sql/e3_01_privileges.sql
~/novabank/sql/e3_02_privileges_tests.sql
```

Exécuter le script de configuration des privilèges :

```bash
sudo -u postgres psql -d bankdb -f ~/novabank/sql/e3_01_privileges.sql
```

Exécuter le script de tests :

```bash
sudo -u postgres psql -d bankdb -f ~/novabank/sql/e3_02_privileges_tests.sql
```

## 3. Contrôle des droits

Vérifier les rôles existants :

```sql
SELECT
    rolname,
    rolsuper,
    rolcreatedb,
    rolcanlogin
FROM pg_roles
WHERE rolname IN (
    'app_grp',
    'analystes',
    'support',
    'auditeurs',
    'app_user',
    'analyste_user',
    'support_user',
    'auditeur_user'
)
ORDER BY rolname;
```

Vérifier les privilèges sur les tables :

```sql
SELECT
    grantee,
    table_schema,
    table_name,
    privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'core'
ORDER BY grantee, table_name, privilege_type;
```

## 4. Paramètres de sécurité

Le script de configuration peut également définir des paramètres de session, notamment `statement_timeout`, afin de limiter la durée d'exécution des requêtes.

Les privilèges par défaut peuvent être configurés avec `ALTER DEFAULT PRIVILEGES` pour appliquer automatiquement certains droits aux futurs objets créés par le rôle concerné.

---

# E4 — Vues et vues matérialisées

## 1. Vue de support : `core.v_clients_support`

Cette vue expose les informations nécessaires au support tout en limitant l'accès aux données personnelles.

Les noms sont masqués et la date de naissance est ramenée à l'année.

Exemple de définition :

```sql
CREATE OR REPLACE VIEW core.v_clients_support
WITH (security_barrier = true)
AS
SELECT
    id_client,
    'Client masqué'::text AS nom,
    EXTRACT(YEAR FROM date_naissance)::integer AS annee_naissance
FROM core.clients;
```

Accorder l'accès au groupe support :

```sql
GRANT SELECT ON core.v_clients_support TO support;
```

La vue permet au support de consulter les informations nécessaires sans exposer directement les noms complets.

## 2. Vue modifiable : `core.v_comptes_courants`

Cette vue limite les données visibles aux comptes courants.

```sql
CREATE OR REPLACE VIEW core.v_comptes_courants AS
SELECT
    id_compte,
    id_client,
    solde,
    type
FROM core.comptes
WHERE type = 'courant'
WITH LOCAL CHECK OPTION;
```

Accorder les droits de consultation et de modification :

```sql
GRANT SELECT ON core.v_comptes_courants TO app_grp;
GRANT UPDATE (solde, type) ON core.v_comptes_courants TO app_grp;
```

La clause `WITH LOCAL CHECK OPTION` empêche une modification via cette vue de créer une ligne qui ne respecte plus son filtre.

## 3. Vue matérialisée : `core.mv_synthese_clients`

La vue matérialisée stocke une synthèse des comptes par client.

```sql
CREATE MATERIALIZED VIEW core.mv_synthese_clients AS
SELECT
    c.id_client,
    COUNT(co.id_compte) AS nombre_comptes,
    COALESCE(SUM(co.solde), 0) AS solde_total
FROM core.clients c
LEFT JOIN core.comptes co
    ON co.id_client = c.id_client
GROUP BY c.id_client;
```

Créer un index unique pour permettre le rafraîchissement concurrent :

```sql
CREATE UNIQUE INDEX idx_mv_synthese_clients_id
ON core.mv_synthese_clients (id_client);
```

Autoriser les analystes à consulter la synthèse :

```sql
GRANT SELECT ON core.mv_synthese_clients TO analystes;
```

Rafraîchir la vue matérialisée :

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY core.mv_synthese_clients;
```

**À noter :** le rafraîchissement concurrent nécessite un index unique approprié et une vue matérialisée déjà remplie.

## 4. Tests de validation

Vérifier la vue de support :

```sql
SELECT *
FROM core.v_clients_support
LIMIT 10;
```

Vérifier la vue des comptes courants :

```sql
SELECT *
FROM core.v_comptes_courants
LIMIT 10;
```

Vérifier la synthèse :

```sql
SELECT *
FROM core.mv_synthese_clients
LIMIT 10;
```

Les tests doivent confirmer que les informations personnelles sont masquées, que la vue des comptes courants respecte son filtre et que les analystes peuvent consulter la synthèse.

---

# E5 — Indexation et benchmarks

## 1. Objectif

L'objectif est de comparer plusieurs stratégies d'indexation PostgreSQL et d'observer leur effet sur les performances des requêtes.

Les scripts de cette étape sont :

```text
~/novabank/sql/e5_01_indexes_creation.sql
~/novabank/sql/e5_02_indexes_benchmarks.sql
```

Exécuter la création des index :

```bash
sudo -u postgres psql -d bankdb -f ~/novabank/sql/e5_01_indexes_creation.sql
```

Exécuter les benchmarks :

```bash
sudo -u postgres psql -d bankdb -f ~/novabank/sql/e5_02_indexes_benchmarks.sql
```

## 2. Stratégies étudiées

### Index B-tree composite

Un index B-tree composite est utile lorsque les requêtes filtrent sur plusieurs colonnes.

Exemple :

```sql
CREATE INDEX idx_ecritures_compte_date
ON core.ecritures (id_compte, date_operation);
```

### Index fonctionnel

Un index fonctionnel peut accélérer les recherches insensibles à la casse lorsque la requête utilise la même expression.

```sql
CREATE INDEX idx_clients_nom_lower
ON core.clients (lower(nom));
```

Exemple de requête compatible :

```sql
SELECT *
FROM core.clients
WHERE lower(nom) = lower('Dupont');
```

### Index GIN avec trigrammes

L'extension `pg_trgm` permet d'accélérer certaines recherches textuelles, notamment les recherches partielles.

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX idx_clients_nom_trgm
ON core.clients
USING GIN (nom gin_trgm_ops);
```

Exemple :

```sql
SELECT *
FROM core.clients
WHERE nom ILIKE '%dup%';
```

### Index partiel

Un index partiel ne conserve que les lignes correspondant à une condition.

```sql
CREATE INDEX idx_comptes_inactifs
ON core.comptes (id_client)
WHERE statut != 'actif';
```

Il peut réduire la taille de l'index si seule une partie des lignes est concernée par les requêtes.

### Index BRIN

Un index BRIN est compact et peut être intéressant pour de grandes tables dont les valeurs suivent approximativement l'ordre physique des lignes.

Exemple :

```sql
CREATE INDEX idx_ecritures_date_brin
ON core.ecritures
USING BRIN (date_operation);
```

Son efficacité dépend notamment de la corrélation entre l'ordre physique des lignes et les valeurs indexées.

## 3. Mesure des performances

Utiliser `EXPLAIN ANALYZE` pour examiner les plans d'exécution et mesurer le temps réel des requêtes.

```sql
EXPLAIN ANALYZE
SELECT *
FROM core.ecritures
WHERE id_compte = 100
ORDER BY date_operation;
```

Pour une comparaison pertinente, il faut utiliser les mêmes requêtes et les mêmes données pour chaque stratégie.

Les temps peuvent varier selon la machine, le cache, la charge du serveur et l'état des statistiques PostgreSQL.

## 4. Résultats observés

Les résultats relevés pendant les tests sont les suivants :

| Mesure | Résultat observé |
|---|---:|
| Première mesure | 0,741 ms |
| Deuxième mesure | 0,152 ms |
| Troisième mesure | 0,237 ms |
| Recherche portant sur 100 % des comptes courants | Parcours séquentiel |
| Taille de la table | 73 MB |
| Taille d'un index B-tree | 30 MB |
| Taille d'un index BRIN | 24 kB |
| Taille de l'index partiel | 8192 octets |

Ces chiffres correspondent aux mesures effectuées dans l'environnement de test. Ils ne constituent pas des performances garanties : les résultats dépendent du jeu de données et des conditions d'exécution.

Un parcours séquentiel peut être préférable lorsqu'une requête doit lire une grande partie de la table. Un index n'est donc pas systématiquement plus rapide.

---

# Conclusion

Les étapes E0 à E5 couvrent la préparation de l'environnement, l'installation de PostgreSQL, la création de la base NovaBank, la gestion des rôles, la sécurisation des accès aux données et l'optimisation des performances.

Les scripts SQL et shell restent les références pour les opérations détaillées. Après chaque étape, il est recommandé de vérifier les résultats avant de passer à la suivante.

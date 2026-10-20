
# NovaBank Core — Système d'information bancaire PostgreSQL

Socle de base de données **PostgreSQL 18**, durci, automatisé et audité pour l'infrastructure bancaire **NovaBank Core**.

Ce projet applique les principes de défense en profondeur :

- Isolation réseau et filtrage des connexions.
- Principe du moindre privilège.
- Intégrité et immuabilité des écritures comptables.
- Isolation des transactions et prévention des interblocages.
- Traçabilité des opérations et journalisation d'audit.
- Sauvegarde, restauration et validation automatisées.

---

## Sommaire

- [Architecture du dépôt](#architecture-du-dépôt)
- [E0 — Environnement système](#e0--environnement-système-et-machine-virtuelle)
- [E1 — Installation et sécurisation](#e1--déploiement-du-serveur-et-durcissement-réseau)
- [E2 — Modèle relationnel et données](#e2--modèle-relationnel-intégrité-et-volumétrie)
- [E3 — Gestion des rôles et privilèges](#e3--modèle-daccès-rbac)
- [E4 — Vues sécurisées](#e4--vues-sécurisées-et-vues-matérialisées)
- [E5 — Indexation et performances](#e5--stratégies-dindexation-et-performances)
- [E6 — Triggers et audit](#e6--immuabilité-et-journalisation-daudit)
- [E7 — Procédures stockées](#e7--procédures-stockées-et-virements-atomiques)
- [E8 — Tests, sauvegarde et restauration](#e8--tests-sauvegarde-et-restauration)
- [Reconstruction complète](#reconstruction-complète)

---

## Architecture du dépôt

```text
novabank/
├── README.md
├── rebuild.sh
├── scripts/
│   ├── install_server.sh
│   └── backup_restore.sh
├── sql/
│   ├── 01_setup.sql
│   ├── 02_schema_data.sql
│   ├── 03_privileges.sql
│   ├── 04_views.sql
│   ├── 05_indexes.sql
│   ├── 06_triggers.sql
│   ├── 07_procedures.sql
│   └── 08_tests_all.sql
└── backups/
```

| Fichier | Rôle |
|---|---|
| `rebuild.sh` | Reconstruction complète et validation du projet |
| `scripts/install_server.sh` | Installation du système, PostgreSQL 18 et configuration UFW |
| `scripts/backup_restore.sh` | Sauvegarde, restauration et contrôle d'intégrité |
| `sql/01_setup.sql` | Initialisation et configuration de la base |
| `sql/02_schema_data.sql` | Schéma `core`, contraintes et données de test |
| `sql/03_privileges.sql` | Rôles, groupes et privilèges |
| `sql/04_views.sql` | Vues sécurisées et vue matérialisée |
| `sql/05_indexes.sql` | Index B-tree, GIN et BRIN |
| `sql/06_triggers.sql` | Audit, immuabilité et contrôles métier |
| `sql/07_procedures.sql` | Procédure de virement atomique |
| `sql/08_tests_all.sql` | Tests et assertions de validation |

---

## E0 — Environnement système et machine virtuelle

### Configuration générale

- **Système d'exploitation :** Debian ou Ubuntu Server.
- **Base de données :** PostgreSQL 18.
- **Réseau local :** `127.0.0.1/32` et `::1/128`.
- **Réseau d'administration :** `192.168.56.0/24`.
- **Adresse IP typique de la VM :** `192.168.56.10`.
- **Administration :** utilisateur non privilégié disposant de `sudo`.
- **Authentification SSH :** connexion par clés.

L'objectif est de séparer l'administration système des accès à la base de données et de limiter les connexions aux réseaux autorisés.

---

## E1 — Déploiement du serveur et durcissement réseau

L'installation de PostgreSQL 18 et la configuration du serveur sont automatisées par `scripts/install_server.sh`.

### 1. Modifier le script

```bash
nano ~/novabank/scripts/install_server.sh
```

### 2. Autoriser son exécution

```bash
chmod +x ~/novabank/scripts/install_server.sh
```

### 3. Lancer le déploiement

```bash
sudo ~/novabank/scripts/install_server.sh
```

### 4. Configuration de sécurité

#### Configuration PostgreSQL

Fichier : `/etc/postgresql/18/main/conf.d/99-novabank.conf`

Les paramètres principaux comprennent :

```ini
listen_addresses = '*'
password_encryption = 'scram-sha-256'
log_connections = on
log_statement = 'all'
```

- `listen_addresses` définit les interfaces sur lesquelles PostgreSQL écoute.
- `password_encryption` utilise SCRAM-SHA-256 pour le stockage des mots de passe.
- `log_connections` journalise les connexions.
- `log_statement` définit la journalisation des instructions SQL.

> **Attention :** `log_statement = 'all'` peut générer un volume important de journaux et enregistrer des données sensibles. Son utilisation doit être adaptée à l'environnement et à la politique de conservation des logs.

#### Règles d'authentification

Fichier : `/etc/postgresql/18/main/pg_hba.conf`

Les règles prévues distinguent les catégories d'accès :

1. Administration locale du rôle `postgres` par socket UNIX avec authentification `peer`.
2. Accès local à `bankdb` pour le propriétaire et le groupe applicatif.
3. Accès des groupes `analystes`, `support` et `auditeurs` depuis le réseau d'administration.
4. Refus des connexions qui ne correspondent pas aux règles autorisées.

Les règles de `pg_hba.conf` sont évaluées dans l'ordre : la première règle correspondante est appliquée.

#### Pare-feu UFW

- Le port `22/tcp` est ouvert avant l'activation du pare-feu pour éviter de perdre la connexion SSH.
- Le port `5432/tcp` est limité au sous-réseau `192.168.56.0/24`.

### 5. Vérifier la configuration

Vérifier les éventuelles erreurs dans les règles d'authentification :

```bash
sudo -u postgres psql -c "
SELECT
    line_number,
    type,
    database,
    user_name,
    address,
    auth_method,
    error
FROM pg_hba_file_rules
WHERE error IS NOT NULL;
"
```

Vérifier les paramètres PostgreSQL :

```bash
sudo -u postgres psql \
  -c "SHOW listen_addresses;" \
  -c "SHOW password_encryption;"
```

Vérifier le pare-feu :

```bash
sudo ufw status verbose
```

---

## E2 — Modèle relationnel, intégrité et volumétrie

Le schéma applicatif `core` regroupe les principales entités bancaires. Les contraintes déclaratives protègent les données et les tests de volumétrie permettent d'étudier les performances.

### 1. Modifier le script SQL

```bash
nano ~/novabank/sql/02_schema_data.sql
```

### 2. Modèle de données

| Table | Description |
|---|---|
| `core.clients` | Informations relatives aux clients |
| `core.comptes` | Comptes bancaires rattachés aux clients |
| `core.virements` | Journal des ordres de virement |
| `core.ecritures` | Grand livre comptable des débits et crédits |

### 3. Contraintes d'intégrité

- `ck_clients_majeur` : impose l'âge légal prévu par le modèle.
- `ck_comptes_solde_positif` : empêche les soldes négatifs.

La contrainte d'âge est décrite par l'expression :

```sql
date_naissance <= CURRENT_DATE - INTERVAL '18 years'
```

La contrainte de solde utilise :

```sql
solde >= 0.00
```

### 4. Jeu de données

Le script initialise les volumes suivants :

- 10 000 clients.
- 20 000 comptes courants et comptes d'épargne.
- 1 000 000 d'écritures générées pseudo-aléatoirement.

La fonction `setseed()` est utilisée pour rendre les générations pseudo-aléatoires reproductibles dans les conditions prévues par le script.

---

## E3 — Modèle d'accès RBAC

La gestion des autorisations repose sur le contrôle d'accès par rôles (*Role-Based Access Control*, RBAC) et sur le principe du moindre privilège.

L'accès est organisé en trois niveaux : base de données, schéma et objets.

### 1. Modifier le script

```bash
nano ~/novabank/sql/03_privileges.sql
```

### 2. Groupes techniques

Les rôles de groupe sont déclarés avec l'attribut `NOLOGIN`.

| Groupe | Fonction |
|---|---|
| `app_grp` | Accès utilisé par l'application bancaire |
| `analystes` | Analyse financière et décisionnelle |
| `support` | Assistance clientèle et opérations de support |
| `auditeurs` | Audit et contrôle de conformité |

Les utilisateurs applicatifs sont :

- `app_user`
- `analyste_user`
- `support_user`
- `auditeur_user`

Ils sont rattachés aux groupes correspondant à leurs fonctions.

### 3. Politique des trois portes

#### Porte 1 — Base de données

Les rôles autorisés reçoivent le privilège `CONNECT` sur `bankdb`.

#### Porte 2 — Schéma

Les rôles concernés reçoivent `USAGE` sur le schéma `core`.

#### Porte 3 — Objets

Les droits sont accordés selon la fonction :

- **Auditeurs :** lecture des tables autorisées.
- **Support :** accès limité aux vues prévues pour le support.
- **Application :** exécution des procédures stockées pour les opérations métier.

Les modifications directes des comptes et des écritures sont interdites au rôle applicatif lorsque les opérations doivent obligatoirement passer par les procédures métier.

Les privilèges implicites de `PUBLIC` sont révoqués conformément à la politique de sécurité définie dans le script.

### 4. Limitation du temps d'exécution

Les délais configurés sont :

| Utilisateur | `statement_timeout` |
|---|---:|
| `analyste_user` | `15s` |
| `support_user` | `5s` |
| `auditeur_user` | `30s` |

Ces limites évitent qu'une requête reste active trop longtemps.

---

## E4 — Vues sécurisées et vues matérialisées

Les vues limitent l'exposition directe des données et fournissent des interfaces adaptées aux différents profils.

### 1. Modifier le script

```bash
nano ~/novabank/sql/04_views.sql
```

### 2. Vue de support

Objet : `core.v_clients_support`

Cette vue masque les données personnelles en présentant :

- Le nom et le prénom sous une forme masquée, par exemple `N***`.
- L'année de naissance plutôt que la date complète.

Elle permet au personnel de support d'accéder aux informations nécessaires sans exposer toutes les données personnelles.

### 3. Vue des comptes courants

Objet : `core.v_comptes_courants`

Cette vue ne présente que les comptes dont le type est `courant`.

La clause `WITH CHECK OPTION` empêche une modification effectuée par l'intermédiaire de la vue de faire sortir la ligne de son périmètre.

### 4. Vue matérialisée de synthèse

Objet : `core.mv_synthese_clients`

Cette vue matérialisée calcule, pour chaque client :

- Le nombre de comptes.
- L'encours total consolidé.

Elle permet de stocker le résultat d'une requête analytique afin d'éviter de recalculer systématiquement la synthèse.

Le rafraîchissement est réalisé sur demande selon la stratégie définie dans le script SQL.

---

## E5 — Stratégies d'indexation et performances

Cette étape compare plusieurs types d'index sur un jeu de données contenant un million d'écritures.

### 1. Modifier le script

```bash
nano ~/novabank/sql/05_indexes.sql
```

### 2. Index B-tree partiel

L'index B-tree partiel sur `core.comptes(client_id)` cible les comptes actifs.

Il permet de réduire la taille de l'index et d'accélérer les requêtes correspondant au prédicat défini.

### 3. Index GIN avec trigrammes

L'extension `pg_trgm` permet d'accélérer certaines recherches textuelles approximatives ou partielles.

L'index concerne les noms et prénoms dans `core.clients` et vise notamment les recherches avec `ILIKE '%...%'`.

### 4. Index BRIN

L'index BRIN porte sur `core.ecritures(date_ecriture)`.

Il est adapté aux grandes tables lorsque les valeurs de la colonne suivent approximativement l'ordre physique des lignes, comme cela peut être le cas pour des écritures chronologiques.

Sa taille peut être nettement inférieure à celle d'un index B-tree, mais son efficacité dépend de la corrélation des données.

---

## E6 — Immuabilité et journalisation d'audit

Cette étape protège le grand livre comptable contre les modifications interdites et ajoute une traçabilité des opérations sensibles.

### 1. Modifier le script

```bash
nano ~/novabank/sql/06_triggers.sql
```

### 2. Déclencheurs prévus

| Déclencheur | Fonction |
|---|---|
| `trg_ecritures_no_update_delete` | Interdit les opérations `UPDATE` et `DELETE` sur `core.ecritures` |
| `trg_ecritures_no_truncate` | Interdit le `TRUNCATE` du grand livre |
| `trg_audit_clients` | Journalise les modifications de `core.clients` |
| `trg_virements_fraud_check` | Contrôle les montants de virements considérés comme suspects |

### 3. Journalisation

Le déclencheur d'audit alimente `core.audit_logs` avec des informations telles que :

- L'utilisateur à l'origine de l'opération.
- L'horodatage.
- Le type d'opération.
- L'état antérieur et l'état postérieur au format JSONB.

Ces mécanismes contribuent à la traçabilité des opérations. Ils doivent être complétés par des contrôles de permissions afin d'empêcher les utilisateurs non autorisés de désactiver les triggers ou de modifier les journaux.

---

## E7 — Procédures stockées et virements atomiques

Les virements sont exécutés dans une transaction unique afin de préserver la cohérence entre les soldes, les écritures et le journal des virements.

### 1. Modifier le script

```bash
nano ~/novabank/sql/07_procedures.sql
```

### 2. Procédure `core.sp_virement`

Signature prévue :

```text
(p_source bigint,
 p_destination bigint,
 p_montant numeric,
 OUT p_virement_id bigint)
```

### 3. Contrôles métier

La procédure doit assurer les opérations suivantes :

1. Verrouiller les comptes concernés.
2. Acquérir les verrous dans un ordre déterministe pour réduire le risque de *deadlock*.
3. Vérifier que le solde source couvre le montant demandé.
4. Rejeter le virement si les contrôles métier échouent.
5. Enregistrer les écritures au débit et au crédit.
6. Mettre à jour les soldes.
7. Insérer le virement dans `core.virements`.

Toutes les opérations liées au virement doivent réussir ensemble ou être annulées ensemble.

---

## E8 — Tests, sauvegarde et restauration

Cette étape vérifie les contraintes, les autorisations, les mécanismes d'audit et la capacité à restaurer une sauvegarde.

### 1. Sauvegarde et restauration

Script : `scripts/backup_restore.sh`

Modifier le script :

```bash
nano ~/novabank/scripts/backup_restore.sh
```

Le rendre exécutable :

```bash
chmod +x ~/novabank/scripts/backup_restore.sh
```

Lancer le cycle de sauvegarde et de restauration :

```bash
~/novabank/scripts/backup_restore.sh
```

### 2. Fonctionnement attendu

Le script réalise les opérations suivantes :

1. Créer un dump PostgreSQL au format custom compressé avec `pg_dump -Fc`.
2. Créer une base temporaire nommée `bankdb_temp`.
3. Restaurer le schéma et les données dans cette base.
4. Comparer le nombre d'écritures entre la base d'origine et la copie restaurée.
5. Supprimer la base temporaire après validation.

Les sauvegardes sont stockées dans le répertoire `backups/`.

### 3. Suite de tests

Script : `sql/08_tests_all.sql`

Modifier le fichier :

```bash
nano ~/novabank/sql/08_tests_all.sql
```

Exécuter les tests :

```bash
sudo -u postgres psql -d bankdb \
  -f ~/novabank/sql/08_tests_all.sql
```

### 4. Scénarios de validation

| Étape | Vérifications prévues |
|---|---|
| E2 | Rejet des clients mineurs et des soldes négatifs |
| E3 | Refus des opérations non autorisées et lecture des écritures par les auditeurs |
| E4 | Masquage des noms et respect du filtre de la vue des comptes courants |
| E6 | Rejet des modifications interdites et journalisation des changements clients |
| E7 | Réussite d'un virement valide et rejet d'un virement dépassant le solde disponible |

---

## Reconstruction complète

Le script `rebuild.sh`, situé à la racine du dépôt, orchestre la reconstruction du projet depuis un environnement préparé.

### 1. Modifier le script

```bash
nano ~/novabank/rebuild.sh
```

### 2. Autoriser son exécution

```bash
chmod +x ~/novabank/rebuild.sh
```

### 3. Lancer la reconstruction

```bash
~/novabank/rebuild.sh
```

### 4. Séquence prévue

Le script :

1. Demande une confirmation à l'opérateur.
2. Supprime la base `bankdb` et nettoie les rôles concernés.
3. Recrée le rôle propriétaire `bank_owner`.
4. Initialise le schéma `core`.
5. Déploie les rôles applicatifs et leurs privilèges.
6. Exécute les scripts SQL dans l'ordre prévu.
7. Lance la suite de tests globale.

> **Attention :** la reconstruction supprime la base existante. Vérifiez vos sauvegardes et assurez-vous de cibler le bon environnement avant de l'exécuter.

---

## Conclusion

NovaBank Core regroupe les mécanismes essentiels d'une base de données bancaire :

- Déploiement et durcissement du serveur PostgreSQL.
- Modélisation relationnelle et contraintes d'intégrité.
- Contrôle d'accès RBAC.
- Vues sécurisées et synthèses analytiques.
- Indexation adaptée aux requêtes.
- Immuabilité comptable et audit.
- Virements transactionnels.
- Sauvegarde, restauration et tests automatisés.

Les scripts constituent la référence pour le comportement effectivement déployé. Les commandes et scénarios décrits dans ce README doivent être validés dans l'environnement cible avant toute utilisation en production.

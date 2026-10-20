#!/usr/bin/env bash
# Rebuilds the entire NovaBank cluster: roles via postgres, objects via bank_owner.
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="${BASE_DIR}/sql"

echo "=========================================================="
echo " ATTENTION : Ce script supprime et recrée intégralement"
echo " la base bankdb et les rôles du projet NovaBank."
echo "=========================================================="
read -rp "Confirmez-vous la réinitialisation totale ? (oui/non) : " rep
if [[ "${rep}" != "oui" ]]; then
    echo "Opération annulée."
    exit 0
fi

echo "[1/4] Suppression et initialisation de la base et du propriétaire (rôle : postgres)..."
sudo -u postgres psql << 'EOF'
DROP DATABASE IF EXISTS bankdb WITH (FORCE);
DROP ROLE IF EXISTS app_user, analyste_user, support_user, auditeur_user;
DROP ROLE IF EXISTS app_grp, analystes, support, auditeurs;
DROP ROLE IF EXISTS bank_owner;

CREATE ROLE bank_owner WITH LOGIN CREATEDB PASSWORD 'bank_secure_pass';
CREATE DATABASE bankdb OWNER bank_owner;
\c bankdb
CREATE SCHEMA core AUTHORIZATION bank_owner;
GRANT ALL ON SCHEMA core TO bank_owner;
EOF

echo "[2/4] Déploiement des rôles et privilèges de base — E3 (rôle : postgres)..."
sudo -u postgres psql -d bankdb < "${SQL_DIR}/03_privileges.sql"

echo "[3/4] Déploiement des objets et logique métier — E2, E4, E5, E6, E7 (rôle : bank_owner)..."
export PGPASSWORD='bank_secure_pass'

psql -h 127.0.0.1 -U bank_owner -d bankdb < "${SQL_DIR}/02_schema_data.sql"
psql -h 127.0.0.1 -U bank_owner -d bankdb < "${SQL_DIR}/04_views.sql"
psql -h 127.0.0.1 -U bank_owner -d bankdb < "${SQL_DIR}/05_indexes.sql"
psql -h 127.0.0.1 -U bank_owner -d bankdb < "${SQL_DIR}/06_triggers.sql"
psql -h 127.0.0.1 -U bank_owner -d bankdb < "${SQL_DIR}/07_procedures.sql"

unset PGPASSWORD

echo "[4/4] Exécution de la suite de tests globale — E8..."
sudo -u postgres psql -d bankdb < "${SQL_DIR}/08_tests_all.sql"

echo "=========================================================="
echo " Reconstitution NovaBank terminée et validée à 100% !"
echo "=========================================================="

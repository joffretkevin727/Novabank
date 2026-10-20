#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${HOME}/novabank/backups"
BACKUP_FILE="${BACKUP_DIR}/bankdb_$(date +%Y%m%d_%H%M%S).dump"
TEMP_DB="bankdb_temp"

echo "[1/4] Sauvegarde de bankdb au format custom (-Fc)..."
sudo -u postgres pg_dump -Fc bankdb > "${BACKUP_FILE}"
ls -lh "${BACKUP_FILE}"

echo "[2/4] Création de la base temporaire de test..."
sudo -u postgres dropdb --if-exists "${TEMP_DB}"
sudo -u postgres createdb -O bank_owner "${TEMP_DB}"

echo "[3/4] Restauration dans ${TEMP_DB}..."
sudo -u postgres pg_restore -d "${TEMP_DB}" < "${BACKUP_FILE}"

echo "[4/4] Comparaison des volumétries..."
COUNT_PROD=$(sudo -u postgres psql -d bankdb -tAc "SELECT count(*) FROM core.ecritures;")
COUNT_TEMP=$(sudo -u postgres psql -d "${TEMP_DB}" -tAc "SELECT count(*) FROM core.ecritures;")

echo "core.ecritures -> Original : ${COUNT_PROD} | Restauré : ${COUNT_TEMP}"

if [ "${COUNT_PROD}" -eq "${COUNT_TEMP}" ]; then
    echo "Succès : Sauvegarde et restauration 100% conformes."
else
    echo "Erreur : Écart de volumétrie détecté." >&2
    exit 1
fi

sudo -u postgres dropdb "${TEMP_DB}"
echo "Base temporaire nettoyée."

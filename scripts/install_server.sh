#!/usr/bin/env bash
# Arrêt immédiat si une commande échoue, variable indéfinie ou tube défaillant
set -euo pipefail

# Vérifier que l'utilisateur est root
if [[ "${EUID}" -ne 0 ]]; then
    echo "Erreur : ce script doit être exécuté avec les privilèges root (sudo)." >&2
    exit 1
fi

echo "[1/6] Mise à jour des paquets et installation..."
apt-get update -y
apt-get install -y postgresql postgresql-client ufw

# Détection dynamique du répertoire de configuration du cluster PostgreSQL
PG_VER=$(pg_lsclusters -h | awk '{print $1}' | head -n1)
PG_CLUSTER=$(pg_lsclusters -h | awk '{print $2}' | head -n1)
PG_DIR="/etc/postgresql/${PG_VER}/${PG_CLUSTER}"
CONF_D="${PG_DIR}/conf.d"

mkdir -p "${CONF_D}"

echo "[2/6] Configuration des paramètres PostgreSQL (99-novabank.conf)..."
cat << 'EOF' > "${CONF_D}/99-novabank.conf"
# Paramètres E1 NovaBank Core
listen_addresses = '*'
password_encryption = 'scram-sha-256'
log_connections = on
log_statement = 'all'
EOF

echo "[3/6] Configuration du contrôle d'accès (pg_hba.conf)..."
# Sauvegarde unique d'origine
if [[ ! -f "${PG_DIR}/pg_hba.conf.orig" ]]; then
    cp "${PG_DIR}/pg_hba.conf" "${PG_DIR}/pg_hba.conf.orig"
fi

cat << 'EOF' > "${PG_DIR}/pg_hba.conf"
# ==============================================================================
# NovaBank Core - Matrice d'accès HBA (Ordre strict E1)
# PostgreSQL évalue de haut en bas et s'arrête à la 1re règle correspondante.
# ==============================================================================

# TYPE  DATABASE        USER                        ADDRESS                 METHOD

# (1) Administrateur local postgres (socket UNIX)
local   all             postgres                                            peer

# (2) Propriétaire et application : depuis la VM uniquement (loopback)
host    bankdb          bank_owner                  127.0.0.1/32            scram-sha-256
host    bankdb          bank_owner                  ::1/128                 scram-sha-256
host    bankdb          +app_grp                    127.0.0.1/32            scram-sha-256
host    bankdb          +app_grp                    ::1/128                 scram-sha-256

# (3) Analystes, support et auditeurs : depuis le réseau d'administration (LAN VM)
host    bankdb          +analystes                  192.168.56.0/24         scram-sha-256
host    bankdb          +support                    192.168.56.0/24         scram-sha-256
host    bankdb          +auditeurs                  192.168.56.0/24         scram-sha-256

# (4) Tout le reste est explicitement rejeté
host    all             all                         0.0.0.0/0               reject
host    all             all                         ::/0                    reject
local   all             all                                                 reject
EOF

echo "[4/6] Configuration du pare-feu UFW..."
# Règles autorisées AVANT l'activation pour préserver la connexion SSH
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow from 192.168.56.0/24 to any port 5432 proto tcp comment 'PostgreSQL NovaBank LAN'
ufw --force enable

echo "[5/6] Redémarrage de PostgreSQL..."
# Un restart est requis car listen_addresses a le contexte postmaster (pg_settings)
systemctl restart postgresql
systemctl enable postgresql

echo "[6/6] Validation de l'état du service..."
pg_lsclusters
systemctl is-active --quiet postgresql && echo "PostgreSQL est actif et opérationnel."

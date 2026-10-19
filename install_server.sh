#!/usr/bin/env bash
# Arrêt immédiat si une commande échoue ou si une variable est indéfinie
set -euo pipefail

# Vérifier que l'utilisateur est root
if [[ "${EUID}" -ne 0 ]]; then
    echo "Erreur : ce script doit être exécuté avec les privilèges root (sudo)." >&2
    exit 1
fi

echo ">> Mise à jour des paquets et installation..."
apt-get update -y
apt-get install -y postgresql postgresql-client ufw

PG_DIR="/etc/postgresql/18/main"
CONF_D="${PG_DIR}/conf.d"

mkdir -p "${CONF_D}"

echo ">> Configuration des paramètres PostgreSQL (conf.d)..."
cat << 'EOF' > "${CONF_D}/99-novabank.conf"
listen_addresses = '*'
password_encryption = 'scram-sha-256'
log_connections = on
log_statement = 'all'
EOF

chown -R postgres:postgres "${CONF_D}"
chmod 644 "${CONF_D}/99-novabank.conf"

echo ">> Configuration des accès réseau (pg_hba.conf)..."
cat << 'EOF' > "${PG_DIR}/pg_hba.conf"
# 1. Administrateur local postgres (socket)
local   all             postgres                                peer

# 2. Propriétaire et application (local VM)
local   all             all                                     scram-sha-256
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256

# 3. Analystes, support et auditeurs (réseau hôte)
host    all             +analystes      192.168.56.0/24         scram-sha-256
host    all             +support        192.168.56.0/24         scram-sha-256
host    all             +auditeurs      192.168.56.0/24         scram-sha-256

# 4. Rejet strict de tout le reste
host    all             all             0.0.0.0/0               reject
host    all             all             ::/0                    reject
EOF

chown postgres:postgres "${PG_DIR}/pg_hba.conf"
chmod 640 "${PG_DIR}/pg_hba.conf"

echo ">> Redémarrage du service PostgreSQL..."
systemctl restart postgresql
systemctl enable postgresql

echo ">> Configuration du pare-feu UFW..."
# Autorisation de SSH AVANT l'activation du pare-feu
ufw allow OpenSSH
# Autorisation de PostgreSQL uniquement depuis le réseau d'administration
ufw allow from 192.168.56.0/24 to any port 5432 proto tcp
ufw --force enable

echo ">> Déploiement terminé avec succès."

-- Creates strategic indexes: composite, functional, partial, BRIN, and GIN.
SET search_path TO core, public;

-- Extension trigrammes pour recherche textuelle avancée
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA core;

-- 1. Index composite (clé étrangère + tri) sur les écritures
CREATE INDEX IF NOT EXISTS idx_ecritures_compte_date 
ON core.ecritures(compte_id, date_operation DESC);

-- 2. Index fonctionnel pour recherche insensible à la casse
CREATE INDEX IF NOT EXISTS idx_clients_lower_nom 
ON core.clients(lower(nom));

-- 3. Index GIN trigramme pour recherche partielle ILIKE '%texte%'
CREATE INDEX IF NOT EXISTS idx_clients_nom_trgm 
ON core.clients USING gin (nom core.gin_trgm_ops);

-- 4. Index partiel sur les statuts minoritaires (ex. inactifs/suspendus)
CREATE INDEX IF NOT EXISTS idx_clients_statut_inactif 
ON core.clients(client_id) 
WHERE statut != 'actif'::core.statut_client;

-- 5. Index BRIN sur les écritures (date corrélée physiquement)
CREATE INDEX IF NOT EXISTS idx_ecritures_brin_date 
ON core.ecritures USING brin (date_operation);

-- Mise à jour impérative des statistiques du catalogue
ANALYZE core.clients;
ANALYZE core.comptes;
ANALYZE core.ecritures;

-- Measures query performance and compares table vs index disk footprints.
SET search_path TO core, public;

-- Mesure 1 : Relevé de compte filtré et trié (doit faire un Index Scan sans Sort)
EXPLAIN (ANALYZE, BUFFERS)
SELECT compte_id, date_operation, montant, balance_after
FROM core.ecritures
WHERE compte_id = 42
ORDER BY date_operation DESC
LIMIT 50;

-- Mesure 2 : Recherche insensible à la casse (utilise l'index fonctionnel)
EXPLAIN (ANALYZE, BUFFERS)
SELECT client_id, nom, prenom
FROM core.clients
WHERE lower(nom) = 'dupont';

-- Mesure 3 : Recherche floue (utilise l'index GIN trigramme)
EXPLAIN (ANALYZE, BUFFERS)
SELECT client_id, nom, prenom
FROM core.clients
WHERE nom ILIKE '%pon%';

-- Mesure 4 : Agrégat mensuel via BRIN (évite la lecture de la table entière)
EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(montant)
FROM core.ecritures
WHERE date_operation BETWEEN '2026-01-01' AND '2026-01-31';

-- Mesure 5 : Démonstration de l'index inutile / ignoré (Seq Scan attendu)
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM core.comptes
WHERE type = 'courant'::core.type_compte;

-- Mesure 6 : Comparaison de la taille disque des index et tables
SELECT 
    schemaname || '.' || relname AS objet,
    pg_size_pretty(pg_relation_size(relid)) AS taille_relation,
    pg_size_pretty(pg_total_relation_size(relid)) AS taille_totale
FROM pg_catalog.pg_statio_user_tables
WHERE schemaname = 'core'
ORDER BY pg_total_relation_size(relid) DESC;

SELECT 
    schemaname || '.' || indexrelname AS index,
    pg_size_pretty(pg_relation_size(indexrelid)) AS taille_index,
    idx_scan AS nombre_utilisations
FROM pg_catalog.pg_stat_user_indexes
WHERE schemaname = 'core'
ORDER BY pg_relation_size(indexrelid) DESC;

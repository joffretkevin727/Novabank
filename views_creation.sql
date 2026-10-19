-- Creates security-focused, updatable, and materialized views based on core schema.
SET search_path TO core, public;

-- 1. Vue support : masquage des données nominatives (initiale + ***)
CREATE OR REPLACE VIEW core.v_clients_support
WITH (security_barrier = true) AS
SELECT 
    client_id,
    left(prenom, 1) || '***' AS prenom,
    left(nom, 1) || '***' AS nom,
    date_part('year', date_naissance) AS annee_naissance,
    statut
FROM core.clients;

GRANT SELECT ON core.v_clients_support TO support;

-- 2. Vue modifiable : restreinte aux comptes courants avec CHECK OPTION
CREATE OR REPLACE VIEW core.v_comptes_courants AS
SELECT 
    compte_id,
    client_id,
    type,
    solde,
    ouvert_le
FROM core.comptes
WHERE type = 'courant'::core.type_compte
WITH LOCAL CHECK OPTION;

GRANT SELECT, UPDATE(solde, type) ON core.v_comptes_courants TO app_grp;

-- 3. Vue matérialisée : synthèse client avec index unique pour rafraîchissement à chaud
CREATE MATERIALIZED VIEW core.mv_synthese_clients AS
SELECT 
    c.client_id,
    count(co.compte_id) AS nb_comptes,
    coalesce(sum(co.solde), 0) AS encours_total,
    now() AS derniere_maj
FROM core.clients c
LEFT JOIN core.comptes co ON co.client_id = c.client_id
GROUP BY c.client_id;

CREATE UNIQUE INDEX idx_mv_synthese_clients_id ON core.mv_synthese_clients(client_id);

GRANT SELECT ON core.mv_synthese_clients TO analystes;

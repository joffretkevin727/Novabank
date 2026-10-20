-- init_e2.sql : Création de la structure et injection de 1 000 000 d'écritures
\c bankdb

SET search_path TO core, public;

-- Nettoyage si réexécution
DROP TABLE IF EXISTS core.ecritures CASCADE;
DROP TABLE IF EXISTS core.virements CASCADE;
DROP TABLE IF EXISTS core.comptes CASCADE;
DROP TABLE IF EXISTS core.clients CASCADE;
DROP TYPE IF EXISTS core.type_ecriture CASCADE;
DROP TYPE IF EXISTS core.type_compte CASCADE;
DROP TYPE IF EXISTS core.statut_client CASCADE;

-- 1. Types énumérés
CREATE TYPE core.statut_client AS ENUM ('actif', 'suspendu', 'cloture');
CREATE TYPE core.type_compte AS ENUM ('courant', 'epargne');
CREATE TYPE core.type_ecriture AS ENUM ('depot', 'retrait', 'virement');

-- 2. Tables avec contraintes
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

-- 3. Génération des données reproductibles
SELECT setseed(0.42);

-- 10 000 clients majeurs
INSERT INTO core.clients (nom, prenom, date_naissance)
SELECT 'Nom_' || g, 'Prenom_' || g, DATE '1980-01-01' + ((g % 10000) || ' days')::interval
FROM generate_series(1, 10000) g;

-- 20 000 comptes
INSERT INTO core.comptes (client_id, type, solde, ouvert_le)
SELECT 1 + (g % 10000), 'courant'::core.type_compte, 0.00, TIMESTAMPTZ '2026-01-01 08:00:00+00'
FROM generate_series(1, 20000) g;

-- Table temporaire pour les opérations
CREATE TEMP TABLE tmp_brut (
    compte_id bigint,
    virement_id bigint,
    type core.type_ecriture,
    montant numeric(14,2),
    date_op timestamptz
);

-- 20 000 dépôts initiaux (1 par compte pour éviter tout solde négatif)
INSERT INTO tmp_brut
SELECT g, NULL, 'depot'::core.type_ecriture, 10000.00, TIMESTAMPTZ '2026-01-01 09:00:00+00'
FROM generate_series(1, 20000) g;

-- 490 000 virements = 980 000 écritures (débit + crédit avec cast explicite)
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
SELECT compte_source_id, virement_id, 'virement'::core.type_ecriture, -montant, execute_le FROM vir_gen
UNION ALL
SELECT compte_destination_id, virement_id, 'virement'::core.type_ecriture, montant, execute_le FROM vir_gen;

-- Insertion dans core.ecritures avec calcul du solde cumulé par fenêtre
INSERT INTO core.ecritures (compte_id, virement_id, type, montant, balance_after, date_operation)
SELECT 
    compte_id,
    virement_id,
    type,
    montant,
    sum(montant) OVER (PARTITION BY compte_id ORDER BY date_op, type) AS balance_after,
    date_op
FROM tmp_brut;

-- Mise à jour des soldes finaux dans la table comptes
UPDATE core.comptes c
SET solde = sub.dernier_solde
FROM (
    SELECT DISTINCT ON (compte_id) compte_id, balance_after AS dernier_solde
    FROM core.ecritures
    ORDER BY compte_id, date_operation DESC
) sub
WHERE c.compte_id = sub.compte_id;

-- Nettoyage et calcul des statistiques
DROP TABLE tmp_brut;
ANALYZE core.ecritures;
ANALYZE core.comptes;

-- Comprehensive test suite covering constraints, roles, views, triggers, and procedures.
\set ON_ERROR_STOP off
SET search_path TO core, public;

\echo '=================================================='
\echo ' 1. CONTRAINTES DE TABLE (E2)'
\echo '=================================================='
-- 1.1 Doit échouer : client mineur (< 18 ans)
INSERT INTO core.clients(nom, prenom, date_naissance, statut)
VALUES ('Test', 'Mineur', CURRENT_DATE - INTERVAL '10 years', 'actif');

-- 1.2 Doit réussir : client majeur
INSERT INTO core.clients(nom, prenom, date_naissance, statut)
VALUES ('Test', 'Majeur', CURRENT_DATE - INTERVAL '25 years', 'actif');

-- 1.3 Doit échouer : solde négatif
INSERT INTO core.comptes(client_id, type, solde)
VALUES (1, 'courant', -50.00);

\echo '=================================================='
\echo ' 2. PRIVILÈGES DES RÔLES (E3)'
\echo '=================================================='
-- 2.1 Doit échouer : analyste_user tente une suppression
SET ROLE analyste_user;
DELETE FROM core.comptes WHERE compte_id = 1;
RESET ROLE;

-- 2.2 Doit réussir : auditeur_user consulte le grand livre
SET ROLE auditeur_user;
SELECT count(*) AS total_ecritures_auditeur FROM core.ecritures;
RESET ROLE;

\echo '=================================================='
\echo ' 3. VUES ET MASQUAGE (E4)'
\echo '=================================================='
-- 3.1 Doit réussir : support_user lit les données masquées
SET ROLE support_user;
SELECT client_id, nom, prenom, annee_naissance FROM core.v_clients_support LIMIT 2;
RESET ROLE;

-- 3.2 Doit échouer : modification hors CHECK OPTION
SET ROLE app_user;
UPDATE core.v_comptes_courants 
SET type = 'epargne'::core.type_compte 
WHERE compte_id = (SELECT compte_id FROM core.v_comptes_courants LIMIT 1);
RESET ROLE;

-- 3.3 Doit réussir : consultation vue matérialisée par analyste_user
SET ROLE analyste_user;
SELECT * FROM core.mv_synthese_clients LIMIT 2;
RESET ROLE;

\echo '=================================================='
\echo ' 4. TRIGGERS (E6)'
\echo '=================================================='
-- 4.1 Doit échouer : modification directe sur le grand livre
UPDATE core.ecritures SET montant = 9999 WHERE ecriture_id = 1;

-- 4.2 Doit échouer : suppression directe sur le grand livre
DELETE FROM core.ecritures WHERE ecriture_id = 1;

-- 4.3 Doit réussir : audit automatique dans core.audit_logs
UPDATE core.clients SET statut = 'suspendu'::core.statut_client WHERE client_id = 1;
SELECT table_name, operation, old_data->>'statut' AS avant, new_data->>'statut' AS apres 
FROM core.audit_logs ORDER BY audit_id DESC LIMIT 1;
UPDATE core.clients SET statut = 'actif'::core.statut_client WHERE client_id = 1;

\echo '=================================================='
\echo ' 5. PROCÉDURE DE VIREMENT (E7)'
\echo '=================================================='
-- 5.1 Doit réussir : virement nominal exécuté par app_user
DO $$
DECLARE
    v_src bigint;
    v_dst bigint;
    v_res bigint;
BEGIN
    SELECT c1.compte_id, c2.compte_id INTO v_src, v_dst
    FROM core.comptes c1, core.comptes c2
    WHERE c1.compte_id <> c2.compte_id AND c1.solde >= 10.00 LIMIT 1;

    SET ROLE app_user;
    CALL core.sp_virement(v_src, v_dst, 10.00, v_res);
    RESET ROLE;

    RAISE NOTICE 'Virement nominal réussi (ID virement : %)', v_res;
END;
$$;

-- 5.2 Doit échouer : virement avec découvert
DO $$
DECLARE
    v_src bigint;
    v_dst bigint;
    v_res bigint;
BEGIN
    SELECT c1.compte_id, c2.compte_id INTO v_src, v_dst
    FROM core.comptes c1, core.comptes c2
    WHERE c1.compte_id <> c2.compte_id LIMIT 1;

    CALL core.sp_virement(v_src, v_dst, 999999999.00, v_res);
END;
$$;

\set ON_ERROR_STOP on
\echo '=================================================='
\echo ' FIN DE LA SUITE DE TESTS'
\echo '=================================================='

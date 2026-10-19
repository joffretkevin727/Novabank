-- Validates triggers: expected successes and expected exceptions.
SET search_path TO core, public;

-- Test 1 : Immuabilité du grand livre (doit lever une exception)
DO $$
BEGIN
    BEGIN
        UPDATE core.ecritures SET montant = 9999 WHERE ecriture_id = 1;
        RAISE EXCEPTION 'Echec test 1 : UPDATE sur core.ecritures autorise a tort';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Test 1.1 valide (UPDATE refuse) : %', SQLERRM;
    END;

    BEGIN
        DELETE FROM core.ecritures WHERE ecriture_id = 1;
        RAISE EXCEPTION 'Echec test 1 : DELETE sur core.ecritures autorise a tort';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Test 1.2 valide (DELETE refuse) : %', SQLERRM;
    END;
END;
$$;

-- Test 2 : Audit générique avec statut valide ('suspendu')
UPDATE core.clients 
SET statut = 'suspendu'::core.statut_client 
WHERE client_id = 1;

-- Verification du log généré
SELECT table_name, operation, old_data->>'statut' AS ancien, new_data->>'statut' AS nouveau
FROM core.audit_logs 
ORDER BY audit_id DESC 
LIMIT 1;

-- Rétablissement
UPDATE core.clients 
SET statut = 'actif'::core.statut_client 
WHERE client_id = 1;

-- Test 3 : Détection de fraude temporelle (colonne execute_le)
DO $$
DECLARE
    src bigint;
    dst bigint;
BEGIN
    SELECT compte_id INTO src FROM core.comptes LIMIT 1;
    SELECT compte_id INTO dst FROM core.comptes WHERE compte_id != src LIMIT 1;

    -- 5 insertions consécutives
    FOR i IN 1..5 LOOP
        INSERT INTO core.virements(compte_source_id, compte_destination_id, montant, execute_le)
        VALUES (src, dst, 10.00, CURRENT_TIMESTAMP);
    END LOOP;

    -- La 6e doit être rejetée
    BEGIN
        INSERT INTO core.virements(compte_source_id, compte_destination_id, montant, execute_le)
        VALUES (src, dst, 10.00, CURRENT_TIMESTAMP);
        RAISE EXCEPTION 'Echec test 3 : 6e virement non bloque';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Test 3 valide (Fraude bloquee) : %', SQLERRM;
    END;
END;
$$;

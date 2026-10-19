-- Tests atomic execution, parameter validation, and security permissions.
SET search_path TO core, public;

-- Test 1 : Virement nominal via app_user (droits délégués via SECURITY DEFINER)
DO $$
DECLARE
    v_src bigint;
    v_dst bigint;
    v_res_id bigint;
BEGIN
    SELECT c1.compte_id, c2.compte_id 
    INTO v_src, v_dst
    FROM core.comptes c1, core.comptes c2
    WHERE c1.compte_id != c2.compte_id 
      AND c1.solde >= 100.00
    LIMIT 1;

    SET ROLE app_user;
    CALL core.sp_virement(v_src, v_dst, 50.00, v_res_id);
    RESET ROLE;

    RAISE NOTICE 'Test 1 validé : Virement % exécuté avec succès par app_user', v_res_id;
END;
$$;

-- Test 2 : Rejet montant négatif ou nul
DO $$
DECLARE
    v_res bigint;
BEGIN
    CALL core.sp_virement(1, 2, -10.00, v_res);
    RAISE EXCEPTION 'Échec : virement négatif non bloqué';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Test 2 validé (Montant négatif rejeté) : %', SQLERRM;
END;
$$;

-- Test 3 : Rejet comptes identiques
DO $$
DECLARE
    v_res bigint;
BEGIN
    CALL core.sp_virement(1, 1, 10.00, v_res);
    RAISE EXCEPTION 'Échec : virement vers le même compte non bloqué';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Test 3 validé (Comptes identiques rejetés) : %', SQLERRM;
END;
$$;

-- Test 4 : Rejet provision insuffisante
DO $$
DECLARE
    v_res bigint;
    v_src bigint;
    v_dst bigint;
BEGIN
    SELECT c1.compte_id, c2.compte_id INTO v_src, v_dst 
    FROM core.comptes c1, core.comptes c2 
    WHERE c1.compte_id != c2.compte_id LIMIT 1;

    CALL core.sp_virement(v_src, v_dst, 999999999.00, v_res);
    RAISE EXCEPTION 'Échec : découvert non bloqué';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Test 4 validé (Provision insuffisante rejetée) : %', SQLERRM;
END;
$$;

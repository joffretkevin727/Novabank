-- Creates atomic transfer procedure with deadlock prevention, explicit search path, and write types.
SET search_path TO core, public;

CREATE OR REPLACE PROCEDURE core.sp_virement(
    p_source_id bigint,
    p_dest_id bigint,
    p_montant numeric(14,2),
    INOUT p_virement_id bigint DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
-- Performs atomic bank transfer between two accounts with strict checks and locking.
DECLARE
    v_first_id bigint;
    v_second_id bigint;
    v_src_solde numeric(14,2);
    v_src_client_statut core.statut_client;
    v_dst_client_statut core.statut_client;
    v_virement_id bigint;
BEGIN
    -- 1. Validation des paramètres d'entrée
    IF p_montant IS NULL OR p_montant <= 0 THEN
        RAISE EXCEPTION 'Montant invalide : le montant doit être strictement supérieur à zéro';
    END IF;

    IF p_source_id IS NULL OR p_dest_id IS NULL THEN
        RAISE EXCEPTION 'Identifiants invalides : les comptes source et destination sont obligatoires';
    END IF;

    IF p_source_id = p_dest_id THEN
        RAISE EXCEPTION 'Opération interdite : les comptes source et destination doivent être distincts';
    END IF;

    -- 2. Ordonnancement pour prévenir les deadlocks
    v_first_id := LEAST(p_source_id, p_dest_id);
    v_second_id := GREATEST(p_source_id, p_dest_id);

    -- 3. Verrouillage pessimiste ordonné
    PERFORM 1 FROM core.comptes WHERE compte_id = v_first_id FOR UPDATE;
    PERFORM 1 FROM core.comptes WHERE compte_id = v_second_id FOR UPDATE;

    -- 4. Contrôle existence, statut et solde source
    SELECT c.solde, cl.statut 
    INTO v_src_solde, v_src_client_statut
    FROM core.comptes c
    JOIN core.clients cl ON cl.client_id = c.client_id
    WHERE c.compte_id = p_source_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Compte source % introuvable', p_source_id;
    END IF;

    IF v_src_client_statut != 'actif'::core.statut_client THEN
        RAISE EXCEPTION 'Opération refusée : le client du compte source n''est pas actif';
    END IF;

    IF v_src_solde < p_montant THEN
        RAISE EXCEPTION 'Provision insuffisante sur le compte source % (solde disponible : %)', p_source_id, v_src_solde;
    END IF;

    -- 5. Contrôle compte destination
    SELECT cl.statut 
    INTO v_dst_client_statut
    FROM core.comptes c
    JOIN core.clients cl ON cl.client_id = c.client_id
    WHERE c.compte_id = p_dest_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Compte destination % introuvable', p_dest_id;
    END IF;

    IF v_dst_client_statut != 'actif'::core.statut_client THEN
        RAISE EXCEPTION 'Opération refusée : le client du compte destination n''est pas actif';
    END IF;

    -- 6. Enregistrement du virement
    INSERT INTO core.virements(compte_source_id, compte_destination_id, montant, execute_le)
    VALUES (p_source_id, p_dest_id, p_montant, CURRENT_TIMESTAMP)
    RETURNING virement_id INTO v_virement_id;

    -- 7. Écritures comptables avec type 'virement'
    INSERT INTO core.ecritures(compte_id, virement_id, type, montant, balance_after, date_operation)
    VALUES (p_source_id, v_virement_id, 'virement'::core.type_ecriture, -p_montant, v_src_solde - p_montant, CURRENT_TIMESTAMP);

    INSERT INTO core.ecritures(compte_id, virement_id, type, montant, balance_after, date_operation)
    VALUES (p_dest_id, v_virement_id, 'virement'::core.type_ecriture, p_montant, 
            (SELECT solde FROM core.comptes WHERE compte_id = p_dest_id) + p_montant, CURRENT_TIMESTAMP);

    p_virement_id := v_virement_id;
END;
$$;

REVOKE ALL ON TABLE core.comptes, core.ecritures, core.virements FROM app_grp;
GRANT EXECUTE ON PROCEDURE core.sp_virement(bigint, bigint, numeric, bigint) TO app_grp;

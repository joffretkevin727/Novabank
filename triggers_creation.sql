-- Implements business integrity, ledger immutability, audit logging, and anti-fraud triggers.
SET search_path TO core, public;

-- Table d'audit générique
CREATE TABLE IF NOT EXISTS core.audit_logs (
    audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name text NOT NULL,
    operation text NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    username text NOT NULL DEFAULT CURRENT_USER,
    old_data jsonb,
    new_data jsonb
);

-- 1. Grand livre immuable (interdiction UPDATE, DELETE, TRUNCATE)
CREATE OR REPLACE FUNCTION core.fn_prevent_ledger_alteration()
RETURNS trigger LANGUAGE plpgsql AS $$
-- Blocks any update, delete, or truncate attempt on ledger entries.
BEGIN
    RAISE EXCEPTION 'Action interdite : le grand livre (core.ecritures) est strictement immuable';
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_ecritures_no_update_delete ON core.ecritures;
CREATE TRIGGER trg_ecritures_no_update_delete
BEFORE UPDATE OR DELETE ON core.ecritures
FOR EACH ROW EXECUTE FUNCTION core.fn_prevent_ledger_alteration();

DROP TRIGGER IF EXISTS trg_ecritures_no_truncate ON core.ecritures;
CREATE TRIGGER trg_ecritures_no_truncate
BEFORE TRUNCATE ON core.ecritures
FOR EACH STATEMENT EXECUTE FUNCTION core.fn_prevent_ledger_alteration();

-- 2. Audit universel via to_jsonb()
CREATE OR REPLACE FUNCTION core.fn_audit_log_record()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
-- Inserts audit metadata and row snapshots into core.audit_logs.
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO core.audit_logs(table_name, operation, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO core.audit_logs(table_name, operation, old_data, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO core.audit_logs(table_name, operation, old_data)
        VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD));
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_clients ON core.clients;
CREATE TRIGGER trg_audit_clients
AFTER INSERT OR UPDATE OR DELETE ON core.clients
FOR EACH ROW EXECUTE FUNCTION core.fn_audit_log_record();

-- 3. Détection de fraude temporelle (max 5 virements en 10 minutes sur execute_le)
CREATE OR REPLACE FUNCTION core.fn_detect_transfer_fraud()
RETURNS trigger LANGUAGE plpgsql AS $$
-- Rejects transfers when rate exceeds threshold within a 10-minute window.
DECLARE
    recent_count integer;
BEGIN
    SELECT count(*) INTO recent_count
    FROM core.virements
    WHERE compte_source_id = NEW.compte_source_id
      AND execute_le >= (CURRENT_TIMESTAMP - INTERVAL '10 minutes');

    IF recent_count >= 5 THEN
        RAISE EXCEPTION 'Alerte fraude : limite de 5 virements en 10 minutes atteinte pour le compte %', NEW.compte_source_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_virements_fraud_check ON core.virements;
CREATE TRIGGER trg_virements_fraud_check
BEFORE INSERT ON core.virements
FOR EACH ROW EXECUTE FUNCTION core.fn_detect_transfer_fraud();

-- 4. Verrouillage pessimiste et mise à jour du solde
CREATE OR REPLACE FUNCTION core.fn_process_account_balance()
RETURNS trigger LANGUAGE plpgsql AS $$
-- Locks target account row and adjusts current balance safely.
DECLARE
    current_solde numeric(14,2);
BEGIN
    SELECT solde INTO current_solde
    FROM core.comptes
    WHERE compte_id = NEW.compte_id
    FOR UPDATE;

    IF (current_solde + NEW.montant) < 0 THEN
        RAISE EXCEPTION 'Provision insuffisante sur le compte % (solde actuel : %, montant : %)', 
            NEW.compte_id, current_solde, NEW.montant;
    END IF;

    UPDATE core.comptes
    SET solde = solde + NEW.montant
    WHERE compte_id = NEW.compte_id;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ecritures_process_balance ON core.ecritures;
CREATE TRIGGER trg_ecritures_process_balance
BEFORE INSERT ON core.ecritures
FOR EACH ROW EXECUTE FUNCTION core.fn_process_account_balance();

-- Sets up roles, default schema privileges, and execution timeouts.
SET search_path TO core, public;

REVOKE ALL ON DATABASE bankdb FROM PUBLIC;
REVOKE ALL ON SCHEMA core FROM PUBLIC;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_grp') THEN
        CREATE ROLE app_grp NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'analystes') THEN
        CREATE ROLE analystes NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'support') THEN
        CREATE ROLE support NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'auditeurs') THEN
        CREATE ROLE auditeurs NOLOGIN;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user LOGIN PASSWORD 'app_pass' IN ROLE app_grp;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'analyste_user') THEN
        CREATE ROLE analyste_user LOGIN PASSWORD 'analyste_pass' IN ROLE analystes;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'support_user') THEN
        CREATE ROLE support_user LOGIN PASSWORD 'support_pass' IN ROLE support;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'auditeur_user') THEN
        CREATE ROLE auditeur_user LOGIN PASSWORD 'auditeur_pass' IN ROLE auditeurs;
    END IF;
END $$;

-- 3 portes : accès base et schéma
GRANT CONNECT ON DATABASE bankdb TO app_grp, analystes, support, auditeurs;
GRANT USAGE ON SCHEMA core TO app_grp, analystes, support, auditeurs;

-- Droits automatiques sur les futures tables créées par bank_owner
ALTER DEFAULT PRIVILEGES FOR ROLE bank_owner IN SCHEMA core
GRANT SELECT ON TABLES TO auditeurs;

-- Configuration des timeouts
ALTER ROLE analyste_user SET statement_timeout = '15s';
ALTER ROLE support_user SET statement_timeout = '5s';
ALTER ROLE auditeur_user SET statement_timeout = '30s';

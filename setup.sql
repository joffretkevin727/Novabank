\c bankdb

-- 1. Nettoyage préventif des rôles si réexécution
REVOKE CONNECT ON DATABASE bankdb FROM PUBLIC;
REVOKE ALL ON SCHEMA core FROM PUBLIC;

-- Supprimer les comptes s'ils existent déjà
DROP ROLE IF EXISTS app_user;
DROP ROLE IF EXISTS analyste_user;
DROP ROLE IF EXISTS support_user;
DROP ROLE IF EXISTS auditeur_user;

-- Supprimer les groupes s'ils existent déjà
DROP ROLE IF EXISTS app_grp;
DROP ROLE IF EXISTS analystes;
DROP ROLE IF EXISTS support;
DROP ROLE IF EXISTS auditeurs;

-- 2. Création des 4 groupes (NOLOGIN)
CREATE ROLE app_grp NOLOGIN;
CREATE ROLE analystes NOLOGIN;
CREATE ROLE support NOLOGIN;
CREATE ROLE auditeurs NOLOGIN;

-- 3. Création des 4 comptes membres (LOGIN hérité du groupe)
CREATE ROLE app_user LOGIN IN ROLE app_grp;
CREATE ROLE analyste_user LOGIN IN ROLE analystes;
CREATE ROLE support_user LOGIN IN ROLE support;
CREATE ROLE auditeur_user LOGIN IN ROLE auditeurs;

-- 4. Attribution des timeouts de sécurité sur les rôles de consultation
ALTER ROLE analyste_user SET statement_timeout = '30s';
ALTER ROLE support_user SET statement_timeout = '30s';
ALTER ROLE auditeur_user SET statement_timeout = '60s';

-- 5. Porte 1 : Droit de connexion à la base bankdb
GRANT CONNECT ON DATABASE bankdb TO app_grp, analystes, support, auditeurs;

-- 6. Porte 2 : Traversée du schéma (USAGE)
GRANT USAGE ON SCHEMA core TO app_grp, analystes, support, auditeurs;

-- 7. Porte 3 : Droits sur les objets de core

-- Application : lecture et écriture sur les flux opérationnels
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA core TO app_grp;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA core TO app_grp;

-- Analystes : lecture seule sur les tables de reporting
GRANT SELECT ON ALL TABLES IN SCHEMA core TO analystes;

-- Support : lecture sur les comptes, clients et écritures (pas de virement direct)
GRANT SELECT ON core.clients, core.comptes, core.ecritures TO support;

-- Auditeurs : lecture seule globale
GRANT SELECT ON ALL TABLES IN SCHEMA core TO auditeurs;

-- 8. Garantir les droits sur les futures tables créées par bank_owner
ALTER DEFAULT PRIVILEGES FOR ROLE bank_owner IN SCHEMA core
    GRANT SELECT, INSERT, UPDATE ON TABLES TO app_grp;

ALTER DEFAULT PRIVILEGES FOR ROLE bank_owner IN SCHEMA core
    GRANT SELECT ON TABLES TO analystes, auditeurs;

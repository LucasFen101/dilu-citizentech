-- =====================================================================
-- Dilu - 00_criar_usuario.sql
-- Executar COMO SYSTEM (ou SYS) conectado ao PDB:  XEPDB1
--   sqlplus system/<senha>@localhost:1521/XEPDB1 @00_criar_usuario.sql
-- Cria o schema ALERTA que guardara todas as tabelas e rotinas PL/SQL.
-- =====================================================================

BEGIN
  EXECUTE IMMEDIATE 'DROP USER alerta CASCADE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1918 THEN RAISE; END IF; -- -1918: usuario nao existe
END;
/

CREATE USER alerta IDENTIFIED BY "Alerta#2026"
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users;

GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
      CREATE PROCEDURE, CREATE TRIGGER, CREATE JOB, CREATE TYPE
  TO alerta;

PROMPT Usuario ALERTA criado.

-- =====================================================================
-- Dilu - 06_migracao_cache_osm.sql
-- So para bancos criados antes do cache do OpenStreetMap (instalacao
-- nova ja sai certa pelo 01_schema.sql). Executar como ALERTA.
-- =====================================================================
CREATE TABLE cache_locais_osm (
  celula     VARCHAR2(30) PRIMARY KEY,
  resposta   CLOB NOT NULL
             CONSTRAINT ck_cache_json CHECK (resposta IS JSON),
  buscado_em TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
);

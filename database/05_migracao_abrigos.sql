-- =====================================================================
-- Dilu - 05_migracao_abrigos.sql
-- So para bancos criados ANTES dos abrigos da comunidade (instalacao nova
-- ja sai certa pelo 01_schema.sql). Executar como ALERTA e, depois,
-- rodar de novo o 02_plsql.sql para criar as rotinas novas.
-- =====================================================================

-- remove os 5 abrigos ficticios "(exemplo)" do seed antigo
DELETE FROM abrigo WHERE nome LIKE '%(exemplo)%';

ALTER TABLE abrigo MODIFY (id_bairro NULL);
ALTER TABLE abrigo ADD (
  origem     VARCHAR2(10) DEFAULT 'OFICIAL' NOT NULL
             CONSTRAINT ck_abrigo_origem CHECK (origem IN ('OFICIAL','COMUNIDADE')),
  tipo       VARCHAR2(40),
  ref_osm    VARCHAR2(30),
  id_usuario NUMBER
             CONSTRAINT fk_abrigo_usuario REFERENCES usuario(id_usuario) ON DELETE SET NULL,
  criado_em  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  expira_em  TIMESTAMP
);
CREATE INDEX ix_abrigo_ativo ON abrigo (ativo, origem);
CREATE INDEX ix_abrigo_osm   ON abrigo (ref_osm);

CREATE TABLE confirmacao_abrigo (
  id_abrigo  NUMBER NOT NULL
             CONSTRAINT fk_confab_abrigo REFERENCES abrigo(id_abrigo) ON DELETE CASCADE,
  id_usuario NUMBER NOT NULL
             CONSTRAINT fk_confab_usuario REFERENCES usuario(id_usuario) ON DELETE CASCADE,
  criado_em  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_confirmacao_abrigo PRIMARY KEY (id_abrigo, id_usuario)
);

ALTER TABLE notificacao DROP CONSTRAINT ck_notif_tipo;
ALTER TABLE notificacao ADD CONSTRAINT ck_notif_tipo CHECK (tipo IN ('RISCO','AJUDA','ABRIGO','SISTEMA'));

COMMIT;

-- =====================================================================
-- Dilu - 01_schema.sql
-- Executar conectado como ALERTA (PDB XEPDB1).
-- Modelo relacional (ver docs/DER_MER.md para o diagrama).
-- =====================================================================

-- ---------------------------------------------------------------- BAIRRO
CREATE TABLE bairro (
  id_bairro      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nome           VARCHAR2(80)  NOT NULL,
  cidade         VARCHAR2(80)  NOT NULL,
  uf             CHAR(2)       NOT NULL,
  latitude       NUMBER(9,6)   NOT NULL,
  longitude      NUMBER(9,6)   NOT NULL,
  score_risco    NUMBER(8,2)   DEFAULT 0 NOT NULL,
  nivel_risco    VARCHAR2(10)  DEFAULT 'BAIXO' NOT NULL
                 CONSTRAINT ck_bairro_nivel
                 CHECK (nivel_risco IN ('BAIXO','MODERADO','ALTO','CRITICO')),
  atualizado_em  TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT uq_bairro UNIQUE (nome, cidade, uf)
);

-- --------------------------------------------------------------- USUARIO
CREATE TABLE usuario (
  id_usuario   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nome         VARCHAR2(100) NOT NULL,
  email        VARCHAR2(150) NOT NULL,
  senha_hash   VARCHAR2(200) NOT NULL,
  telefone     VARCHAR2(20),
  id_bairro    NUMBER CONSTRAINT fk_usuario_bairro REFERENCES bairro(id_bairro),
  criado_em    TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT uq_usuario_email UNIQUE (email)
);

-- ------------------------------------------------------ CONTATO_EMERGENCIA
CREATE TABLE contato_emergencia (
  id_contato   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_usuario   NUMBER NOT NULL
               CONSTRAINT fk_contato_usuario REFERENCES usuario(id_usuario) ON DELETE CASCADE,
  nome         VARCHAR2(100) NOT NULL,
  telefone     VARCHAR2(20)  NOT NULL,
  parentesco   VARCHAR2(40)
);

-- ------------------------------------------------------------ ALAGAMENTO
CREATE TABLE alagamento (
  id_alagamento NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_usuario    NUMBER NOT NULL
                CONSTRAINT fk_alag_usuario REFERENCES usuario(id_usuario),
  id_bairro     NUMBER CONSTRAINT fk_alag_bairro REFERENCES bairro(id_bairro),
  latitude      NUMBER(9,6) NOT NULL,
  longitude     NUMBER(9,6) NOT NULL,
  descricao     VARCHAR2(500),
  gravidade     NUMBER(1) NOT NULL
                CONSTRAINT ck_alag_gravidade CHECK (gravidade BETWEEN 1 AND 4),
  status        VARCHAR2(10) DEFAULT 'ATIVO' NOT NULL
                CONSTRAINT ck_alag_status CHECK (status IN ('ATIVO','RESOLVIDO','EXPIRADO')),
  foto          VARCHAR2(255),
  criado_em     TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  expira_em     TIMESTAMP NOT NULL,
  resolvido_em  TIMESTAMP
);
CREATE INDEX ix_alag_bairro_status ON alagamento (id_bairro, status);
CREATE INDEX ix_alag_status_expira ON alagamento (status, expira_em);
CREATE INDEX ix_alag_usuario       ON alagamento (id_usuario);

-- ------------------------------------------------- CONFIRMACAO_ALAGAMENTO
CREATE TABLE confirmacao_alagamento (
  id_confirmacao NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_alagamento  NUMBER NOT NULL
                 CONSTRAINT fk_conf_alag REFERENCES alagamento(id_alagamento) ON DELETE CASCADE,
  id_usuario     NUMBER NOT NULL
                 CONSTRAINT fk_conf_usuario REFERENCES usuario(id_usuario),
  criado_em      TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT uq_confirmacao UNIQUE (id_alagamento, id_usuario)
);
CREATE INDEX ix_conf_usuario ON confirmacao_alagamento (id_usuario);

-- ----------------------------------------------------------- PEDIDO_AJUDA
CREATE TABLE pedido_ajuda (
  id_pedido    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_usuario   NUMBER NOT NULL
               CONSTRAINT fk_pedido_usuario REFERENCES usuario(id_usuario),
  id_bairro    NUMBER CONSTRAINT fk_pedido_bairro REFERENCES bairro(id_bairro),
  latitude     NUMBER(9,6) NOT NULL,
  longitude    NUMBER(9,6) NOT NULL,
  tipo         VARCHAR2(10) NOT NULL
               CONSTRAINT ck_pedido_tipo CHECK (tipo IN ('AJUDA','SEGURO')),
  mensagem     VARCHAR2(300),
  status       VARCHAR2(10) DEFAULT 'ABERTO' NOT NULL
               CONSTRAINT ck_pedido_status CHECK (status IN ('ABERTO','ATENDIDO')),
  criado_em    TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  atendido_em  TIMESTAMP
);
CREATE INDEX ix_pedido_bairro  ON pedido_ajuda (id_bairro, tipo, status);
CREATE INDEX ix_pedido_usuario ON pedido_ajuda (id_usuario);

-- ---------------------------------------------------------------- ABRIGO
-- Abrigo OFICIAL (cadastrado pela Defesa Civil/prefeitura) ou da COMUNIDADE:
-- um morador marca que um local (escola, ginasio... vindo do OpenStreetMap)
-- esta recebendo pessoas. O da comunidade expira se ninguem confirmar.
CREATE TABLE abrigo (
  id_abrigo   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_bairro   NUMBER
              CONSTRAINT fk_abrigo_bairro REFERENCES bairro(id_bairro),
  nome        VARCHAR2(120) NOT NULL,
  endereco    VARCHAR2(200),
  latitude    NUMBER(9,6) NOT NULL,
  longitude   NUMBER(9,6) NOT NULL,
  capacidade  NUMBER(6),
  telefone    VARCHAR2(20),
  ativo       CHAR(1) DEFAULT 'S' NOT NULL
              CONSTRAINT ck_abrigo_ativo CHECK (ativo IN ('S','N')),
  origem      VARCHAR2(10) DEFAULT 'OFICIAL' NOT NULL
              CONSTRAINT ck_abrigo_origem CHECK (origem IN ('OFICIAL','COMUNIDADE')),
  tipo        VARCHAR2(40),
  ref_osm     VARCHAR2(30),
  id_usuario  NUMBER
              CONSTRAINT fk_abrigo_usuario REFERENCES usuario(id_usuario) ON DELETE SET NULL,
  criado_em   TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  expira_em   TIMESTAMP
);
CREATE INDEX ix_abrigo_bairro ON abrigo (id_bairro);
CREATE INDEX ix_abrigo_ativo  ON abrigo (ativo, origem);
CREATE INDEX ix_abrigo_osm    ON abrigo (ref_osm);

-- ----------------------------------------------------- CACHE_LOCAIS_OSM
-- Resposta do OpenStreetMap (Overpass) por "celula" do mapa (~2 km).
-- Evita repetir a mesma busca e mantem o app funcionando se o Overpass cair.
CREATE TABLE cache_locais_osm (
  celula     VARCHAR2(30) PRIMARY KEY,
  resposta   CLOB NOT NULL
             CONSTRAINT ck_cache_json CHECK (resposta IS JSON),
  buscado_em TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
);

-- ------------------------------------------------- CONFIRMACAO_ABRIGO
-- Moradores que confirmam que o abrigo da comunidade continua funcionando.
CREATE TABLE confirmacao_abrigo (
  id_abrigo  NUMBER NOT NULL
             CONSTRAINT fk_confab_abrigo REFERENCES abrigo(id_abrigo) ON DELETE CASCADE,
  id_usuario NUMBER NOT NULL
             CONSTRAINT fk_confab_usuario REFERENCES usuario(id_usuario) ON DELETE CASCADE,
  criado_em  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_confirmacao_abrigo PRIMARY KEY (id_abrigo, id_usuario)
);

-- ----------------------------------------------------------- NOTIFICACAO
CREATE TABLE notificacao (
  id_notificacao NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_usuario     NUMBER NOT NULL
                 CONSTRAINT fk_notif_usuario REFERENCES usuario(id_usuario) ON DELETE CASCADE,
  tipo           VARCHAR2(10) NOT NULL
                 CONSTRAINT ck_notif_tipo CHECK (tipo IN ('RISCO','AJUDA','ABRIGO','SISTEMA')),
  titulo         VARCHAR2(120) NOT NULL,
  mensagem       VARCHAR2(300),
  lida           CHAR(1) DEFAULT 'N' NOT NULL
                 CONSTRAINT ck_notif_lida CHECK (lida IN ('S','N')),
  criado_em      TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
);
CREATE INDEX ix_notif_usuario ON notificacao (id_usuario, lida);

-- -------------------------------------------------------- HISTORICO_RISCO
CREATE TABLE historico_risco (
  id_historico  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_bairro     NUMBER NOT NULL
                CONSTRAINT fk_hist_bairro REFERENCES bairro(id_bairro),
  score_risco   NUMBER(8,2) NOT NULL,
  nivel_risco   VARCHAR2(10) NOT NULL,
  registrado_em TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
);
CREATE INDEX ix_hist_bairro ON historico_risco (id_bairro, registrado_em);

-- ============================================================ VIEW
-- Indicadores por bairro (alimenta o painel do app).
CREATE OR REPLACE VIEW vw_indicadores_bairro AS
SELECT b.id_bairro,
       b.nome,
       b.cidade,
       b.uf,
       b.latitude,
       b.longitude,
       b.score_risco,
       b.nivel_risco,
       (SELECT COUNT(*) FROM alagamento a
         WHERE a.id_bairro = b.id_bairro AND a.status = 'ATIVO')           AS alagamentos_ativos,
       (SELECT COUNT(*) FROM alagamento a
         WHERE a.id_bairro = b.id_bairro
           AND a.criado_em >= SYSTIMESTAMP - INTERVAL '1' DAY)             AS relatos_24h,
       (SELECT COUNT(*) FROM pedido_ajuda p
         WHERE p.id_bairro = b.id_bairro AND p.tipo = 'AJUDA'
           AND p.status = 'ABERTO')                                        AS pedidos_abertos,
       (SELECT COUNT(*) FROM abrigo s
         WHERE s.id_bairro = b.id_bairro AND s.ativo = 'S')                AS abrigos
  FROM bairro b;

-- Numeros gerais do Dilu (tela "Dilu em numeros").
CREATE OR REPLACE VIEW vw_dilu_numeros AS
SELECT (SELECT COUNT(*) FROM usuario)                                          AS moradores,
       (SELECT COUNT(*) FROM alagamento)                                       AS relatos_total,
       (SELECT COUNT(*) FROM alagamento WHERE status = 'ATIVO')                AS relatos_ativos,
       (SELECT COUNT(*) FROM alagamento WHERE status = 'RESOLVIDO')            AS relatos_resolvidos,
       (SELECT COUNT(*) FROM confirmacao_alagamento)                           AS confirmacoes,
       (SELECT COUNT(*) FROM pedido_ajuda WHERE tipo = 'AJUDA')                AS pedidos_ajuda,
       (SELECT COUNT(*) FROM pedido_ajuda WHERE tipo = 'AJUDA' AND status = 'ATENDIDO') AS pedidos_atendidos,
       (SELECT COUNT(*) FROM notificacao WHERE tipo = 'RISCO')                 AS avisos_risco
  FROM dual;

-- Resumo pessoal de cada morador (aba "Conta" do app).
CREATE OR REPLACE VIEW vw_resumo_usuario AS
SELECT u.id_usuario,
       (SELECT COUNT(*) FROM alagamento a
         WHERE a.id_usuario = u.id_usuario)                                      AS relatos_total,
       (SELECT COUNT(*) FROM alagamento a
         WHERE a.id_usuario = u.id_usuario AND a.status = 'ATIVO')               AS relatos_ativos,
       (SELECT COUNT(*) FROM alagamento a
         WHERE a.id_usuario = u.id_usuario AND a.status = 'RESOLVIDO')           AS relatos_resolvidos,
       (SELECT COUNT(*) FROM confirmacao_alagamento c
          JOIN alagamento a ON a.id_alagamento = c.id_alagamento
         WHERE a.id_usuario = u.id_usuario)                                      AS confirmacoes_recebidas,
       (SELECT COUNT(*) FROM confirmacao_alagamento c
         WHERE c.id_usuario = u.id_usuario)                                      AS confirmacoes_dadas,
       (SELECT COUNT(*) FROM pedido_ajuda p
         WHERE p.id_usuario = u.id_usuario AND p.tipo = 'AJUDA')                 AS pedidos_ajuda
  FROM usuario u;
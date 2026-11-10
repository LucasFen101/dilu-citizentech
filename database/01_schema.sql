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
  -- localizacao opcional: sem GPS o pedido vale mesmo assim (nunca se grava um ponto inventado)
  latitude     NUMBER(9,6),
  longitude    NUMBER(9,6),
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

-- ----------------------------------------------------------- LOCAL_SEGURO
-- Locais seguros cadastrados pela comunidade: ponto alto (para deixar o
-- carro ou se proteger da agua), local que acolhe pessoas, ponto de
-- encontro e ponto de doacao. Os vizinhos avaliam se e mesmo seguro.
CREATE TABLE local_seguro (
  id_local   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_usuario NUMBER
             CONSTRAINT fk_local_usuario REFERENCES usuario(id_usuario) ON DELETE SET NULL,
  id_bairro  NUMBER
             CONSTRAINT fk_local_bairro REFERENCES bairro(id_bairro),
  nome       VARCHAR2(80) NOT NULL,
  tipo       VARCHAR2(15) NOT NULL
             CONSTRAINT ck_local_tipo CHECK (tipo IN ('PONTO_ALTO','ACOLHIMENTO','PONTO_ENCONTRO','DOACAO')),
  descricao  VARCHAR2(300),
  latitude   NUMBER(9,6) NOT NULL,
  longitude  NUMBER(9,6) NOT NULL,
  ativo      CHAR(1) DEFAULT 'S' NOT NULL
             CONSTRAINT ck_local_ativo CHECK (ativo IN ('S','N')),
  criado_em  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
);
CREATE INDEX ix_local_bairro  ON local_seguro (id_bairro);
CREATE INDEX ix_local_usuario ON local_seguro (id_usuario);
CREATE INDEX ix_local_ativo   ON local_seguro (ativo);

-- ---------------------------------------------------------- LUGAR_USUARIO
-- Lugares que o morador acompanha (casa, trabalho, faculdade...): o app
-- mostra chuva acumulada e alertas de clima de cada um. Maximo 5 por pessoa.
CREATE TABLE lugar_usuario (
  id_lugar   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_usuario NUMBER NOT NULL
             CONSTRAINT fk_lugar_usuario REFERENCES usuario(id_usuario) ON DELETE CASCADE,
  apelido    VARCHAR2(40) NOT NULL,
  tipo       VARCHAR2(10) DEFAULT 'OUTRO' NOT NULL
             CONSTRAINT ck_lugar_tipo CHECK (tipo IN ('CASA','TRABALHO','ESTUDO','FAMILIA','OUTRO')),
  latitude   NUMBER(9,6) NOT NULL,
  longitude  NUMBER(9,6) NOT NULL,
  id_bairro  NUMBER
             CONSTRAINT fk_lugar_bairro REFERENCES bairro(id_bairro),
  criado_em  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT uq_lugar_apelido UNIQUE (id_usuario, apelido)
);
CREATE INDEX ix_lugar_usuario ON lugar_usuario (id_usuario);

-- -------------------------------------------------------- AVALIACAO_LOCAL
-- Voto de cada vizinho: o local e seguro (S) ou nao e (N). Um voto por pessoa.
CREATE TABLE avaliacao_local (
  id_local   NUMBER NOT NULL
             CONSTRAINT fk_aval_local REFERENCES local_seguro(id_local) ON DELETE CASCADE,
  id_usuario NUMBER NOT NULL
             CONSTRAINT fk_aval_usuario REFERENCES usuario(id_usuario) ON DELETE CASCADE,
  seguro     CHAR(1) NOT NULL
             CONSTRAINT ck_aval_seguro CHECK (seguro IN ('S','N')),
  criado_em  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_avaliacao_local PRIMARY KEY (id_local, id_usuario)
);

-- ----------------------------------------------------------- NOTIFICACAO
CREATE TABLE notificacao (
  id_notificacao NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_usuario     NUMBER NOT NULL
                 CONSTRAINT fk_notif_usuario REFERENCES usuario(id_usuario) ON DELETE CASCADE,
  tipo           VARCHAR2(10) NOT NULL
                 CONSTRAINT ck_notif_tipo CHECK (tipo IN ('RISCO','AJUDA','LOCAL','SISTEMA')),
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
       (SELECT COUNT(*) FROM local_seguro s
         WHERE s.id_bairro = b.id_bairro AND s.ativo = 'S')                AS locais_seguros
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
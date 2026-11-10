-- =====================================================================
-- Dilu - 02_plsql.sql
-- Funcoes, package, triggers e job (PL/SQL). Executar como ALERTA.
-- Regra: as rotinas NAO fazem COMMIT; quem chama (API) controla a transacao.
-- Erros de negocio usam RAISE_APPLICATION_ERROR (-20001 a -20099).
-- =====================================================================

-- ------------------------------------------------ FN_DISTANCIA_KM
-- Distancia entre dois pontos (formula de Haversine), em km.
CREATE OR REPLACE FUNCTION fn_distancia_km (
  p_lat1 NUMBER, p_lon1 NUMBER,
  p_lat2 NUMBER, p_lon2 NUMBER
) RETURN NUMBER DETERMINISTIC IS
  c_raio CONSTANT NUMBER := 6371;
  c_rad  CONSTANT NUMBER := 0.017453292519943295;
  v_dlat NUMBER;
  v_dlon NUMBER;
  v_a    NUMBER;
BEGIN
  v_dlat := (p_lat2 - p_lat1) * c_rad;
  v_dlon := (p_lon2 - p_lon1) * c_rad;
  v_a := POWER(SIN(v_dlat / 2), 2)
       + COS(p_lat1 * c_rad) * COS(p_lat2 * c_rad) * POWER(SIN(v_dlon / 2), 2);
  RETURN c_raio * 2 * ASIN(LEAST(1, SQRT(v_a)));
END fn_distancia_km;
/

-- ------------------------------------------------ FN_BAIRRO_PROXIMO
-- Bairro cadastrado mais proximo do ponto (ate 15 km), ou NULL.
CREATE OR REPLACE FUNCTION fn_bairro_proximo (
  p_lat NUMBER, p_lon NUMBER
) RETURN NUMBER IS
  v_id   bairro.id_bairro%TYPE;
  v_dist NUMBER;
BEGIN
  SELECT id_bairro, dist
    INTO v_id, v_dist
    FROM (SELECT id_bairro,
                 fn_distancia_km(latitude, longitude, p_lat, p_lon) AS dist
            FROM bairro
           ORDER BY dist)
   WHERE ROWNUM = 1;
  IF v_dist > 15 THEN
    RETURN NULL;
  END IF;
  RETURN v_id;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RETURN NULL;
END fn_bairro_proximo;
/

-- ------------------------------------------------ PACKAGE PKG_ENCHENTE
CREATE OR REPLACE PACKAGE pkg_enchente AS
  FUNCTION fn_score_bairro (p_id_bairro NUMBER) RETURN NUMBER;
  FUNCTION fn_nivel_por_score (p_score NUMBER) RETURN VARCHAR2;

  PROCEDURE sp_recalcular_risco (p_id_bairro NUMBER);

  PROCEDURE sp_cadastrar_usuario (
    p_nome       VARCHAR2,
    p_email      VARCHAR2,
    p_senha_hash VARCHAR2,
    p_telefone   VARCHAR2,
    p_lat        NUMBER,
    p_lon        NUMBER,
    p_id_usuario OUT NUMBER
  );

  PROCEDURE sp_registrar_alagamento (
    p_id_usuario    NUMBER,
    p_lat           NUMBER,
    p_lon           NUMBER,
    p_descricao     VARCHAR2,
    p_gravidade     NUMBER,
    p_foto          VARCHAR2,
    p_id_alagamento OUT NUMBER
  );

  PROCEDURE sp_confirmar_alagamento (p_id_alagamento NUMBER, p_id_usuario NUMBER);
  PROCEDURE sp_resolver_alagamento  (p_id_alagamento NUMBER, p_id_usuario NUMBER);

  PROCEDURE sp_pedir_ajuda (
    p_id_usuario NUMBER,
    p_lat        NUMBER,
    p_lon        NUMBER,
    p_tipo       VARCHAR2,
    p_mensagem   VARCHAR2,
    p_id_pedido  OUT NUMBER
  );

  PROCEDURE sp_marcar_notificacoes_lidas (p_id_usuario NUMBER);
  PROCEDURE sp_expirar_alagamentos (p_qtd OUT NUMBER);

  -- locais seguros da comunidade
  PROCEDURE sp_cadastrar_local (
    p_id_usuario NUMBER,
    p_nome       VARCHAR2,
    p_tipo       VARCHAR2,
    p_descricao  VARCHAR2,
    p_lat        NUMBER,
    p_lon        NUMBER,
    p_id_local   OUT NUMBER
  );
  PROCEDURE sp_avaliar_local (p_id_local NUMBER, p_id_usuario NUMBER, p_seguro VARCHAR2);
  PROCEDURE sp_remover_local (p_id_local NUMBER, p_id_usuario NUMBER);

  -- meus lugares
  PROCEDURE sp_salvar_lugar (
    p_id_usuario NUMBER,
    p_apelido    VARCHAR2,
    p_tipo       VARCHAR2,
    p_lat        NUMBER,
    p_lon        NUMBER,
    p_id_lugar   OUT NUMBER
  );
  PROCEDURE sp_remover_lugar (p_id_lugar NUMBER, p_id_usuario NUMBER);
END pkg_enchente;
/

CREATE OR REPLACE PACKAGE BODY pkg_enchente AS

  ----------------------------------------------------------------------
  -- Score = soma, dos alagamentos ATIVOS do bairro, de
  --         gravidade * (1 + 0,5 * confirmacoes da comunidade)
  ----------------------------------------------------------------------
  FUNCTION fn_score_bairro (p_id_bairro NUMBER) RETURN NUMBER IS
    v_score NUMBER;
  BEGIN
    SELECT NVL(SUM(a.gravidade * (1 + 0.5 *
             (SELECT COUNT(*) FROM confirmacao_alagamento c
               WHERE c.id_alagamento = a.id_alagamento))), 0)
      INTO v_score
      FROM alagamento a
     WHERE a.id_bairro = p_id_bairro
       AND a.status = 'ATIVO';
    RETURN v_score;
  END fn_score_bairro;

  FUNCTION fn_nivel_por_score (p_score NUMBER) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE
             WHEN p_score < 3  THEN 'BAIXO'
             WHEN p_score < 8  THEN 'MODERADO'
             WHEN p_score < 15 THEN 'ALTO'
             ELSE 'CRITICO'
           END;
  END fn_nivel_por_score;

  ----------------------------------------------------------------------
  -- Recalcula score/nivel do bairro e grava historico quando o nivel muda.
  -- O trigger TRG_BAIRRO_NOTIFICA avisa os moradores se o risco subir.
  ----------------------------------------------------------------------
  PROCEDURE sp_recalcular_risco (p_id_bairro NUMBER) IS
    v_score      NUMBER;
    v_nivel      VARCHAR2(10);
    v_nivel_ant  VARCHAR2(10);
  BEGIN
    IF p_id_bairro IS NULL THEN
      RETURN;
    END IF;

    v_score := fn_score_bairro(p_id_bairro);
    v_nivel := fn_nivel_por_score(v_score);

    SELECT nivel_risco INTO v_nivel_ant FROM bairro WHERE id_bairro = p_id_bairro;

    UPDATE bairro
       SET score_risco   = v_score,
           nivel_risco   = v_nivel,
           atualizado_em = SYSTIMESTAMP
     WHERE id_bairro = p_id_bairro;

    IF v_nivel <> v_nivel_ant THEN
      INSERT INTO historico_risco (id_bairro, score_risco, nivel_risco)
      VALUES (p_id_bairro, v_score, v_nivel);
    END IF;
  END sp_recalcular_risco;

  ----------------------------------------------------------------------
  PROCEDURE sp_cadastrar_usuario (
    p_nome       VARCHAR2,
    p_email      VARCHAR2,
    p_senha_hash VARCHAR2,
    p_telefone   VARCHAR2,
    p_lat        NUMBER,
    p_lon        NUMBER,
    p_id_usuario OUT NUMBER
  ) IS
    v_bairro NUMBER;
  BEGIN
    IF p_lat IS NOT NULL AND p_lon IS NOT NULL THEN
      v_bairro := fn_bairro_proximo(p_lat, p_lon);
    END IF;

    INSERT INTO usuario (nome, email, senha_hash, telefone, id_bairro)
    VALUES (TRIM(p_nome), LOWER(TRIM(p_email)), p_senha_hash, p_telefone, v_bairro)
    RETURNING id_usuario INTO p_id_usuario;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20001, UNISTR('E-mail j\00E1 cadastrado.'));
  END sp_cadastrar_usuario;

  ----------------------------------------------------------------------
  -- Registra um alagamento: valida, descobre o bairro pelo GPS, impede
  -- relato duplicado e define a expiracao (3h por nivel de gravidade).
  -- O trigger TRG_ALAGAMENTO_RISCO recalcula o risco do bairro.
  ----------------------------------------------------------------------
  PROCEDURE sp_registrar_alagamento (
    p_id_usuario    NUMBER,
    p_lat           NUMBER,
    p_lon           NUMBER,
    p_descricao     VARCHAR2,
    p_gravidade     NUMBER,
    p_foto          VARCHAR2,
    p_id_alagamento OUT NUMBER
  ) IS
    v_dup NUMBER;
  BEGIN
    IF p_gravidade IS NULL OR p_gravidade NOT BETWEEN 1 AND 4 THEN
      RAISE_APPLICATION_ERROR(-20010, UNISTR('Gravidade deve ser de 1 a 4.'));
    END IF;

    SELECT COUNT(*) INTO v_dup
      FROM alagamento
     WHERE id_usuario = p_id_usuario
       AND status = 'ATIVO'
       AND criado_em >= SYSTIMESTAMP - INTERVAL '10' MINUTE
       AND fn_distancia_km(latitude, longitude, p_lat, p_lon) < 0.05;
    IF v_dup > 0 THEN
      RAISE_APPLICATION_ERROR(-20011, UNISTR('Voc\00EA j\00E1 relatou este local h\00E1 poucos minutos.'));
    END IF;

    INSERT INTO alagamento (id_usuario, id_bairro, latitude, longitude,
                            descricao, gravidade, foto, expira_em)
    VALUES (p_id_usuario, fn_bairro_proximo(p_lat, p_lon), p_lat, p_lon,
            p_descricao, p_gravidade, p_foto,
            SYSTIMESTAMP + NUMTODSINTERVAL(p_gravidade * 3, 'HOUR'))
    RETURNING id_alagamento INTO p_id_alagamento;
  END sp_registrar_alagamento;

  ----------------------------------------------------------------------
  -- Confirmacao da comunidade: aumenta o peso do relato e prolonga 1h.
  ----------------------------------------------------------------------
  PROCEDURE sp_confirmar_alagamento (p_id_alagamento NUMBER, p_id_usuario NUMBER) IS
    v_status alagamento.status%TYPE;
    v_dono   alagamento.id_usuario%TYPE;
  BEGIN
    BEGIN
      SELECT status, id_usuario INTO v_status, v_dono
        FROM alagamento WHERE id_alagamento = p_id_alagamento;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20020, UNISTR('Alagamento n\00E3o encontrado.'));
    END;

    IF v_status <> 'ATIVO' THEN
      RAISE_APPLICATION_ERROR(-20020, UNISTR('Este alagamento n\00E3o est\00E1 mais ativo.'));
    END IF;
    IF v_dono = p_id_usuario THEN
      RAISE_APPLICATION_ERROR(-20022, UNISTR('Voc\00EA n\00E3o pode confirmar o pr\00F3prio relato.'));
    END IF;

    INSERT INTO confirmacao_alagamento (id_alagamento, id_usuario)
    VALUES (p_id_alagamento, p_id_usuario);

    UPDATE alagamento
       SET expira_em = expira_em + INTERVAL '1' HOUR
     WHERE id_alagamento = p_id_alagamento;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20021, UNISTR('Voc\00EA j\00E1 confirmou este alagamento.'));
  END sp_confirmar_alagamento;

  ----------------------------------------------------------------------
  PROCEDURE sp_resolver_alagamento (p_id_alagamento NUMBER, p_id_usuario NUMBER) IS
  BEGIN
    UPDATE alagamento
       SET status = 'RESOLVIDO', resolvido_em = SYSTIMESTAMP
     WHERE id_alagamento = p_id_alagamento
       AND id_usuario = p_id_usuario
       AND status = 'ATIVO';
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20030,
        UNISTR('N\00E3o \00E9 poss\00EDvel resolver: relato inexistente, j\00E1 encerrado ou de outro usu\00E1rio.'));
    END IF;
  END sp_resolver_alagamento;

  ----------------------------------------------------------------------
  -- 'AJUDA' avisa moradores do bairro (trigger). 'SEGURO' encerra
  -- os pedidos de ajuda abertos do proprio usuario.
  -- Sem GPS (p_lat/p_lon nulos) o pedido vale mesmo assim: usa o bairro
  -- do cadastro do morador e nao grava nenhum ponto inventado.
  ----------------------------------------------------------------------
  PROCEDURE sp_pedir_ajuda (
    p_id_usuario NUMBER,
    p_lat        NUMBER,
    p_lon        NUMBER,
    p_tipo       VARCHAR2,
    p_mensagem   VARCHAR2,
    p_id_pedido  OUT NUMBER
  ) IS
    v_bairro pedido_ajuda.id_bairro%TYPE;
    v_lat    pedido_ajuda.latitude%TYPE  := p_lat;
    v_lon    pedido_ajuda.longitude%TYPE := p_lon;
  BEGIN
    IF p_tipo NOT IN ('AJUDA', 'SEGURO') THEN
      RAISE_APPLICATION_ERROR(-20040, 'Tipo deve ser AJUDA ou SEGURO.');
    END IF;

    IF v_lat IS NULL OR v_lon IS NULL THEN
      v_lat := NULL;
      v_lon := NULL;
      SELECT id_bairro INTO v_bairro FROM usuario WHERE id_usuario = p_id_usuario;
    ELSE
      v_bairro := fn_bairro_proximo(v_lat, v_lon);
    END IF;

    IF p_tipo = 'SEGURO' THEN
      UPDATE pedido_ajuda
         SET status = 'ATENDIDO', atendido_em = SYSTIMESTAMP
       WHERE id_usuario = p_id_usuario AND tipo = 'AJUDA' AND status = 'ABERTO';
    END IF;

    INSERT INTO pedido_ajuda (id_usuario, id_bairro, latitude, longitude, tipo, mensagem)
    VALUES (p_id_usuario, v_bairro, v_lat, v_lon, p_tipo, p_mensagem)
    RETURNING id_pedido INTO p_id_pedido;
  END sp_pedir_ajuda;

  ----------------------------------------------------------------------
  PROCEDURE sp_marcar_notificacoes_lidas (p_id_usuario NUMBER) IS
  BEGIN
    UPDATE notificacao SET lida = 'S'
     WHERE id_usuario = p_id_usuario AND lida = 'N';
  END sp_marcar_notificacoes_lidas;

  ----------------------------------------------------------------------
  -- Chamada pelo job agendado: expira relatos vencidos.
  -- (o trigger recalcula o risco dos bairros afetados)
  ----------------------------------------------------------------------
  PROCEDURE sp_expirar_alagamentos (p_qtd OUT NUMBER) IS
  BEGIN
    UPDATE alagamento
       SET status = 'EXPIRADO'
     WHERE status = 'ATIVO' AND expira_em < SYSTIMESTAMP;
    p_qtd := SQL%ROWCOUNT;
  END sp_expirar_alagamentos;

  ----------------------------------------------------------------------
  -- Morador cadastra um local seguro. Valida o tipo, impede repetir o
  -- mesmo ponto (menos de 30 m de outro local ativo) e limita 10 por pessoa.
  -- O trigger TRG_LOCAL_NOTIFICA avisa os moradores do bairro.
  ----------------------------------------------------------------------
  PROCEDURE sp_cadastrar_local (
    p_id_usuario NUMBER,
    p_nome       VARCHAR2,
    p_tipo       VARCHAR2,
    p_descricao  VARCHAR2,
    p_lat        NUMBER,
    p_lon        NUMBER,
    p_id_local   OUT NUMBER
  ) IS
    c_maximo CONSTANT PLS_INTEGER := 10;
    v_qtd    PLS_INTEGER;
  BEGIN
    IF TRIM(p_nome) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20070, UNISTR('Informe o nome do local.'));
    END IF;
    IF p_tipo NOT IN ('PONTO_ALTO', 'ACOLHIMENTO', 'PONTO_ENCONTRO', 'DOACAO') THEN
      RAISE_APPLICATION_ERROR(-20070, UNISTR('Tipo de local inv\00E1lido.'));
    END IF;

    SELECT COUNT(*) INTO v_qtd
      FROM local_seguro
     WHERE ativo = 'S'
       AND fn_distancia_km(latitude, longitude, p_lat, p_lon) < 0.03;
    IF v_qtd > 0 THEN
      RAISE_APPLICATION_ERROR(-20071, UNISTR('J\00E1 existe um local seguro neste ponto. Avalie o que est\00E1 no mapa.'));
    END IF;

    SELECT COUNT(*) INTO v_qtd
      FROM local_seguro
     WHERE id_usuario = p_id_usuario AND ativo = 'S';
    IF v_qtd >= c_maximo THEN
      RAISE_APPLICATION_ERROR(-20072, UNISTR('Voc\00EA j\00E1 cadastrou 10 locais.'));
    END IF;

    INSERT INTO local_seguro (id_usuario, id_bairro, nome, tipo, descricao, latitude, longitude)
    VALUES (p_id_usuario, fn_bairro_proximo(p_lat, p_lon), TRIM(p_nome), p_tipo,
            TRIM(p_descricao), p_lat, p_lon)
    RETURNING id_local INTO p_id_local;
  END sp_cadastrar_local;

  ----------------------------------------------------------------------
  -- Vizinho avalia o local: S = e seguro, N = nao e seguro. Pode mudar o
  -- voto. Com 3 ou mais "nao" e mais "nao" que "sim", o local sai do mapa.
  ----------------------------------------------------------------------
  PROCEDURE sp_avaliar_local (p_id_local NUMBER, p_id_usuario NUMBER, p_seguro VARCHAR2) IS
    v_ativo local_seguro.ativo%TYPE;
    v_dono  local_seguro.id_usuario%TYPE;
    v_sim   PLS_INTEGER;
    v_nao   PLS_INTEGER;
  BEGIN
    IF p_seguro NOT IN ('S', 'N') THEN
      RAISE_APPLICATION_ERROR(-20073, 'Voto deve ser S ou N.');
    END IF;
    BEGIN
      SELECT ativo, id_usuario INTO v_ativo, v_dono
        FROM local_seguro WHERE id_local = p_id_local;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20074, UNISTR('Local n\00E3o encontrado.'));
    END;
    IF v_ativo <> 'S' THEN
      RAISE_APPLICATION_ERROR(-20074, UNISTR('Este local n\00E3o est\00E1 mais no mapa.'));
    END IF;
    IF v_dono = p_id_usuario THEN
      RAISE_APPLICATION_ERROR(-20075, UNISTR('Voc\00EA n\00E3o pode avaliar o local que cadastrou.'));
    END IF;

    MERGE INTO avaliacao_local a
    USING (SELECT p_id_local AS id_local, p_id_usuario AS id_usuario FROM dual) s
       ON (a.id_local = s.id_local AND a.id_usuario = s.id_usuario)
     WHEN MATCHED THEN UPDATE SET seguro = p_seguro, criado_em = SYSTIMESTAMP
     WHEN NOT MATCHED THEN INSERT (id_local, id_usuario, seguro) VALUES (p_id_local, p_id_usuario, p_seguro);

    SELECT COUNT(CASE WHEN seguro = 'S' THEN 1 END),
           COUNT(CASE WHEN seguro = 'N' THEN 1 END)
      INTO v_sim, v_nao
      FROM avaliacao_local WHERE id_local = p_id_local;
    IF v_nao >= 3 AND v_nao > v_sim THEN
      UPDATE local_seguro SET ativo = 'N' WHERE id_local = p_id_local;
    END IF;
  END sp_avaliar_local;

  ----------------------------------------------------------------------
  -- Quem cadastrou pode tirar o local do mapa.
  ----------------------------------------------------------------------
  PROCEDURE sp_remover_local (p_id_local NUMBER, p_id_usuario NUMBER) IS
  BEGIN
    UPDATE local_seguro
       SET ativo = 'N'
     WHERE id_local = p_id_local AND id_usuario = p_id_usuario AND ativo = 'S';
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20076, UNISTR('S\00F3 quem cadastrou pode remover o local.'));
    END IF;
  END sp_remover_local;

  ----------------------------------------------------------------------
  -- Salva um lugar acompanhado (casa, trabalho...). Valida o limite de 5,
  -- o tipo e as coordenadas, e descobre o bairro pelo ponto.
  ----------------------------------------------------------------------
  PROCEDURE sp_salvar_lugar (
    p_id_usuario NUMBER,
    p_apelido    VARCHAR2,
    p_tipo       VARCHAR2,
    p_lat        NUMBER,
    p_lon        NUMBER,
    p_id_lugar   OUT NUMBER
  ) IS
    c_maximo CONSTANT PLS_INTEGER := 5;
    v_total  PLS_INTEGER;
  BEGIN
    IF TRIM(p_apelido) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20060, UNISTR('D\00EA um nome para o lugar.'));
    END IF;
    IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
      RAISE_APPLICATION_ERROR(-20061, UNISTR('Localiza\00E7\00E3o inv\00E1lida.'));
    END IF;

    SELECT COUNT(*) INTO v_total FROM lugar_usuario WHERE id_usuario = p_id_usuario;
    IF v_total >= c_maximo THEN
      RAISE_APPLICATION_ERROR(-20062, UNISTR('Voc\00EA j\00E1 tem 5 lugares. Remova um para adicionar outro.'));
    END IF;

    INSERT INTO lugar_usuario (id_usuario, apelido, tipo, latitude, longitude, id_bairro)
    VALUES (p_id_usuario, TRIM(p_apelido), NVL(p_tipo, 'OUTRO'), p_lat, p_lon, fn_bairro_proximo(p_lat, p_lon))
    RETURNING id_lugar INTO p_id_lugar;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20063, UNISTR('Voc\00EA j\00E1 tem um lugar com esse nome.'));
  END sp_salvar_lugar;

  ----------------------------------------------------------------------
  PROCEDURE sp_remover_lugar (p_id_lugar NUMBER, p_id_usuario NUMBER) IS
  BEGIN
    DELETE FROM lugar_usuario WHERE id_lugar = p_id_lugar AND id_usuario = p_id_usuario;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20064, UNISTR('Lugar n\00E3o encontrado.'));
    END IF;
  END sp_remover_lugar;

END pkg_enchente;
/

SHOW ERRORS

-- ------------------------------------------------ TRIGGER: risco por alagamento
-- Compound trigger evita ORA-04091 (tabela mutante): coleta os bairros
-- afetados linha a linha e recalcula uma vez no fim do comando.
CREATE OR REPLACE TRIGGER trg_alagamento_risco
FOR INSERT OR UPDATE OR DELETE ON alagamento
COMPOUND TRIGGER
  TYPE t_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  g_ids t_ids;

  PROCEDURE marca (p_id NUMBER) IS
  BEGIN
    IF p_id IS NOT NULL THEN
      g_ids(p_id) := p_id;
    END IF;
  END marca;

  AFTER EACH ROW IS
  BEGIN
    IF DELETING THEN
      marca(:OLD.id_bairro);
    ELSE
      marca(:NEW.id_bairro);
    END IF;
  END AFTER EACH ROW;

  AFTER STATEMENT IS
    v_i PLS_INTEGER;
  BEGIN
    v_i := g_ids.FIRST;
    WHILE v_i IS NOT NULL LOOP
      pkg_enchente.sp_recalcular_risco(g_ids(v_i));
      v_i := g_ids.NEXT(v_i);
    END LOOP;
    g_ids.DELETE;
  END AFTER STATEMENT;
END trg_alagamento_risco;
/

-- ------------------------------------------------ TRIGGER: risco por confirmacao
CREATE OR REPLACE TRIGGER trg_confirmacao_risco
FOR INSERT ON confirmacao_alagamento
COMPOUND TRIGGER
  TYPE t_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  g_ids t_ids;

  AFTER EACH ROW IS
  BEGIN
    g_ids(:NEW.id_alagamento) := :NEW.id_alagamento;
  END AFTER EACH ROW;

  AFTER STATEMENT IS
    v_i      PLS_INTEGER;
    v_bairro NUMBER;
  BEGIN
    v_i := g_ids.FIRST;
    WHILE v_i IS NOT NULL LOOP
      SELECT id_bairro INTO v_bairro FROM alagamento WHERE id_alagamento = g_ids(v_i);
      pkg_enchente.sp_recalcular_risco(v_bairro);
      v_i := g_ids.NEXT(v_i);
    END LOOP;
    g_ids.DELETE;
  END AFTER STATEMENT;
END trg_confirmacao_risco;
/

-- ------------------------------------------------ TRIGGER: notifica moradores
-- Quando o risco do bairro SOBE para ALTO ou CRITICO, avisa os moradores.
CREATE OR REPLACE TRIGGER trg_bairro_notifica
AFTER UPDATE OF nivel_risco ON bairro
FOR EACH ROW
WHEN (NEW.nivel_risco <> OLD.nivel_risco
      AND NEW.nivel_risco IN ('ALTO', 'CRITICO')
      AND OLD.nivel_risco <> 'CRITICO')
BEGIN
  INSERT INTO notificacao (id_usuario, tipo, titulo, mensagem)
  SELECT u.id_usuario,
         'RISCO',
         'Risco ' || :NEW.nivel_risco || ' de alagamento em ' || :NEW.nome,
         UNISTR('V\00E1rios relatos da comunidade indicam alagamento. Evite a regi\00E3o e veja os locais seguros no app.')
    FROM usuario u
   WHERE u.id_bairro = :NEW.id_bairro;
END trg_bairro_notifica;
/

-- ------------------------------------------------ TRIGGER: pedido de ajuda
CREATE OR REPLACE TRIGGER trg_pedido_ajuda_notifica
AFTER INSERT ON pedido_ajuda
FOR EACH ROW
WHEN (NEW.tipo = 'AJUDA' AND NEW.id_bairro IS NOT NULL)
BEGIN
  INSERT INTO notificacao (id_usuario, tipo, titulo, mensagem)
  SELECT u.id_usuario,
         'AJUDA',
         UNISTR('Pedido de ajuda perto de voc\00EA'),
         'Um morador de ' || (SELECT b.nome FROM bairro b WHERE b.id_bairro = :NEW.id_bairro)
           || ' precisa de ajuda. Se puder ajudar, acione a Defesa Civil (199) ou os bombeiros (193).'
    FROM usuario u
   WHERE u.id_bairro = :NEW.id_bairro
     AND u.id_usuario <> :NEW.id_usuario;
END trg_pedido_ajuda_notifica;
/

-- ------------------------------------------------ TRIGGER: novo local seguro
-- Quando um morador cadastra um local seguro, avisa os outros moradores do bairro.
CREATE OR REPLACE TRIGGER trg_local_notifica
AFTER INSERT ON local_seguro
FOR EACH ROW
WHEN (NEW.id_bairro IS NOT NULL)
BEGIN
  INSERT INTO notificacao (id_usuario, tipo, titulo, mensagem)
  SELECT u.id_usuario,
         'LOCAL',
         UNISTR('Novo local seguro perto de voc\00EA'),
         SUBSTR('Um vizinho cadastrou "' || :NEW.nome || '" como '
           || CASE :NEW.tipo
                WHEN 'PONTO_ALTO'     THEN 'ponto alto'
                WHEN 'ACOLHIMENTO'    THEN 'local que acolhe pessoas'
                WHEN 'PONTO_ENCONTRO' THEN 'ponto de encontro'
                ELSE TO_CHAR(UNISTR('ponto de doa\00E7\00F5es'))
              END
           || UNISTR('. Veja no mapa e avalie se \00E9 seguro.'), 1, 300)
    FROM usuario u
   WHERE u.id_bairro = :NEW.id_bairro
     AND (u.id_usuario <> :NEW.id_usuario OR :NEW.id_usuario IS NULL);
END trg_local_notifica;
/

-- ------------------------------------------------ JOB: expirar relatos
BEGIN
  BEGIN
    DBMS_SCHEDULER.DROP_JOB('JOB_EXPIRAR_ALAGAMENTOS', force => TRUE);
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'JOB_EXPIRAR_ALAGAMENTOS',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'DECLARE v NUMBER; BEGIN pkg_enchente.sp_expirar_alagamentos(v); COMMIT; END;',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=MINUTELY;INTERVAL=15',
    enabled         => TRUE,
    comments        => 'Expira relatos de alagamento vencidos e recalcula o risco');
END;
/

SHOW ERRORS

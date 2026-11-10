-- =====================================================================
-- Dilu - 04_teste_plsql.sql
-- Cenario de teste das rotinas PL/SQL. Termina com ROLLBACK (nao suja o banco).
-- =====================================================================
SET SERVEROUTPUT ON
SET FEEDBACK OFF

DECLARE
  v_u1 NUMBER; v_u2 NUMBER; v_u3 NUMBER; v_u4 NUMBER;
  v_a1 NUMBER; v_a2 NUMBER; v_p NUMBER; v_qtd NUMBER;
  v_l NUMBER; v_ativo local_seguro.ativo%TYPE;
  v_nivel bairro.nivel_risco%TYPE; v_score bairro.score_risco%TYPE;
  v_n NUMBER; v_bairro NUMBER;

  PROCEDURE mostra (p_titulo VARCHAR2) IS
  BEGIN
    SELECT nivel_risco, score_risco INTO v_nivel, v_score FROM bairro WHERE id_bairro = v_bairro;
    DBMS_OUTPUT.PUT_LINE(RPAD(p_titulo, 38) || ' -> risco=' || v_nivel || ' score=' || v_score);
  END;
BEGIN
  -- tres moradores da Mooca
  pkg_enchente.sp_cadastrar_usuario('Ana',   'ana@teste.com',   'hash', '11900000001', -23.5590, -46.5990, v_u1);
  pkg_enchente.sp_cadastrar_usuario('Bruno', 'bruno@teste.com', 'hash', '11900000002', -23.5595, -46.5985, v_u2);
  pkg_enchente.sp_cadastrar_usuario('Carla', 'carla@teste.com', 'hash', '11900000003', -23.5585, -46.5995, v_u3);
  SELECT id_bairro INTO v_bairro FROM bairro WHERE nome = 'Mooca';
  mostra('Inicio');

  pkg_enchente.sp_registrar_alagamento(v_u1, -23.5590, -46.5990, 'Rua alagada', 3, NULL, v_a1);
  mostra('Relato gravidade 3 (Ana)');

  pkg_enchente.sp_confirmar_alagamento(v_a1, v_u2);
  pkg_enchente.sp_confirmar_alagamento(v_a1, v_u3);
  mostra('+2 confirmacoes');

  pkg_enchente.sp_registrar_alagamento(v_u2, -23.5600, -46.5970, 'Agua na calcada', 4, NULL, v_a2);
  mostra('Segundo relato gravidade 4 (Bruno)');

  SELECT COUNT(*) INTO v_n FROM notificacao WHERE tipo = 'RISCO';
  DBMS_OUTPUT.PUT_LINE('Notificacoes de RISCO geradas: ' || v_n);

  pkg_enchente.sp_pedir_ajuda(v_u1, -23.5590, -46.5990, 'AJUDA', 'Agua entrando em casa', v_p);
  SELECT COUNT(*) INTO v_n FROM notificacao WHERE tipo = 'AJUDA';
  DBMS_OUTPUT.PUT_LINE('Notificacoes de AJUDA aos vizinhos: ' || v_n);

  -- regras de negocio
  BEGIN pkg_enchente.sp_confirmar_alagamento(v_a1, v_u2);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Confirmar 2x       : ' || SQLERRM); END;
  BEGIN pkg_enchente.sp_confirmar_alagamento(v_a1, v_u1);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Confirmar proprio  : ' || SQLERRM); END;
  BEGIN pkg_enchente.sp_registrar_alagamento(v_u1, -23.5590, -46.5990, 'dup', 2, NULL, v_a2);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Relato duplicado   : ' || SQLERRM); END;
  BEGIN pkg_enchente.sp_registrar_alagamento(v_u1, -23.5, -46.5, 'x', 9, NULL, v_a2);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Gravidade invalida : ' || SQLERRM); END;
  BEGIN pkg_enchente.sp_cadastrar_usuario('Ana2', 'ana@teste.com', 'h', NULL, NULL, NULL, v_n);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('E-mail duplicado   : ' || SQLERRM); END;

  -- pedido de ajuda SEM localizacao: vale mesmo assim, no bairro do cadastro
  pkg_enchente.sp_pedir_ajuda(v_u2, NULL, NULL, 'AJUDA', NULL, v_p);
  SELECT COUNT(*) INTO v_n FROM pedido_ajuda
   WHERE id_pedido = v_p AND latitude IS NULL AND id_bairro = v_bairro;
  DBMS_OUTPUT.PUT_LINE('Pedido sem GPS gravado no bairro do morador: ' || v_n);

  -- locais seguros da comunidade
  pkg_enchente.sp_cadastrar_usuario('Davi', 'davi@teste.com', 'hash', NULL, -23.5592, -46.5992, v_u4);
  pkg_enchente.sp_cadastrar_local(v_u1, 'Estacionamento alto', 'PONTO_ALTO', 'Piso 2', -23.5562, -46.5972, v_l);
  SELECT COUNT(*) INTO v_n FROM notificacao WHERE tipo = 'LOCAL';
  DBMS_OUTPUT.PUT_LINE('Avisos de novo local seguro aos vizinhos: ' || v_n);
  pkg_enchente.sp_avaliar_local(v_l, v_u2, 'S');
  BEGIN pkg_enchente.sp_avaliar_local(v_l, v_u1, 'S');
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Avaliar o proprio  : ' || SQLERRM); END;
  BEGIN pkg_enchente.sp_cadastrar_local(v_u2, 'Mesmo ponto', 'DOACAO', NULL, -23.5562, -46.5972, v_n);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Local repetido     : ' || SQLERRM); END;
  pkg_enchente.sp_avaliar_local(v_l, v_u2, 'N'); -- Bruno muda o voto
  pkg_enchente.sp_avaliar_local(v_l, v_u3, 'N');
  pkg_enchente.sp_avaliar_local(v_l, v_u4, 'N');
  SELECT ativo INTO v_ativo FROM local_seguro WHERE id_local = v_l;
  DBMS_OUTPUT.PUT_LINE('Local apos 3 votos "nao e seguro": ativo=' || v_ativo);

  -- meus lugares: maximo de 5 por morador
  FOR i IN 1 .. 5 LOOP
    pkg_enchente.sp_salvar_lugar(v_u1, 'Lugar ' || i, 'OUTRO', -23.5590, -46.5990, v_n);
  END LOOP;
  BEGIN pkg_enchente.sp_salvar_lugar(v_u1, 'Sexto', 'OUTRO', -23.5590, -46.5990, v_n);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Sexto lugar        : ' || SQLERRM); END;

  -- resolver e expirar
  pkg_enchente.sp_resolver_alagamento(v_a1, v_u1);
  mostra('Ana resolveu o relato 1');
  UPDATE alagamento SET expira_em = SYSTIMESTAMP - INTERVAL '1' MINUTE;
  pkg_enchente.sp_expirar_alagamentos(v_qtd);
  mostra('Apos expirar (' || v_qtd || ' relato(s))');

  SELECT COUNT(*) INTO v_n FROM historico_risco WHERE id_bairro = v_bairro;
  DBMS_OUTPUT.PUT_LINE('Mudancas de nivel no historico: ' || v_n);
  DBMS_OUTPUT.PUT_LINE('Distancia Mooca-Pinheiros (km): ' ||
    ROUND(fn_distancia_km(-23.5590, -46.5990, -23.5670, -46.7020), 2));
END;
/
ROLLBACK;

"""Acesso ao Oracle: pool de conexoes e utilitarios.

Boas praticas de memoria/eficiencia aplicadas aqui:
- pool de conexoes reaproveitadas (nao abre uma conexao por requisicao);
- conexao sempre devolvida ao pool (bloco finally), sem vazamento;
- bind variables em todas as consultas (plano de execucao reaproveitado e
  protecao contra SQL injection);
- limite de linhas nas listagens (FETCH FIRST) para nao carregar tudo em memoria.
"""
import re
from contextlib import contextmanager
from typing import Any, Iterator

import oracledb

from . import config

_pool: oracledb.ConnectionPool | None = None


def init_pool() -> None:
    """Cria o pool de conexoes (chamado na inicializacao da API)."""
    global _pool
    if _pool is None:
        _pool = oracledb.create_pool(
            user=config.ORACLE_USER,
            password=config.ORACLE_PASSWORD,
            dsn=config.ORACLE_DSN,
            min=1,
            max=5,
            increment=1,
        )


def close_pool() -> None:
    """Fecha o pool (chamado no desligamento da API)."""
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


@contextmanager
def transaction() -> Iterator[oracledb.Connection]:
    """Entrega uma conexao do pool dentro de uma transacao.

    COMMIT se o bloco terminar bem, ROLLBACK se der erro, e a conexao
    volta sempre ao pool. As procedures PL/SQL nao fazem commit: o
    controle da transacao e daqui.
    """
    if _pool is None:
        init_pool()
    conn = _pool.acquire()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        _pool.release(conn)


def query(conn: oracledb.Connection, sql: str, binds: dict[str, Any] | None = None) -> list[dict]:
    """Executa um SELECT e devolve lista de dicts com chaves em minusculo."""
    with conn.cursor() as cur:
        cur.execute(sql, binds or {})
        cols = [d[0].lower() for d in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]


def query_one(conn: oracledb.Connection, sql: str, binds: dict[str, Any] | None = None) -> dict | None:
    """Como query(), mas devolve apenas a primeira linha (ou None)."""
    rows = query(conn, sql, binds)
    return rows[0] if rows else None


_ORA_APP_ERROR = re.compile(r"ORA-(20\d{3}):\s*(.*)")


def parse_app_error(exc: oracledb.DatabaseError) -> tuple[int, str] | None:
    """Extrai (codigo, mensagem) de um RAISE_APPLICATION_ERROR (ORA-20xxx).

    Devolve None se o erro nao for uma regra de negocio da nossa PL/SQL.
    """
    match = _ORA_APP_ERROR.search(str(exc))
    if not match:
        return None
    return int(match.group(1)), match.group(2).strip()

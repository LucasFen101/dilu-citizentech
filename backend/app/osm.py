"""Busca de locais que costumam virar abrigo (OpenStreetMap / Overpass) com cache no Oracle.

Por que passar pela API em vez de o app chamar o Overpass direto:
- o Overpass e gratuito e fica sobrecarregado com frequencia (erros 502/504);
- a resposta de cada regiao fica guardada no Oracle por 30 dias, entao a
  segunda pessoa da mesma regiao recebe na hora, mesmo com o Overpass fora;
- respeita a politica de uso do Overpass (menos consultas repetidas).
"""
import json

import httpx
import oracledb

from . import db

# servidores publicos do Overpass, tentados em ordem
ESPELHOS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
)
TAMANHO_CELULA = 0.02  # graus (~2 km): pontos proximos dividem o mesmo cache
RAIO_M = 3500  # cobre a celula inteira com folga
VALIDADE_DIAS = 30
_CABECALHO = {"User-Agent": "Dilu/1.0 (projeto academico FIAP - alertas de enchente)"}


def celula(lat: float, lon: float) -> tuple[str, float, float]:
    """Arredonda o ponto para a celula do cache. Devolve (chave, lat_centro, lon_centro)."""
    clat = round(round(lat / TAMANHO_CELULA) * TAMANHO_CELULA, 4)
    clon = round(round(lon / TAMANHO_CELULA) * TAMANHO_CELULA, 4)
    return f"{clat:.2f}:{clon:.2f}", clat, clon


def consulta_overpass(lat: float, lon: float) -> str:
    """Escolas, centros comunitarios e ginasios num raio em volta do ponto."""
    a = f"around:{RAIO_M},{lat:.5f},{lon:.5f}"
    return (
        "[out:json][timeout:25];("
        f'nwr["amenity"="school"]({a});'
        f'nwr["amenity"="community_centre"]({a});'
        f'nwr["leisure"="sports_centre"]({a});'
        f'nwr["leisure"="sports_hall"]({a});'
        ");out center tags 400;"
    )


def _buscar_overpass(lat: float, lon: float) -> str | None:
    """Tenta cada espelho; devolve o JSON (texto) do primeiro que responder."""
    dados = {"data": consulta_overpass(lat, lon)}
    for url in ESPELHOS:
        try:
            r = httpx.post(url, data=dados, headers=_CABECALHO, timeout=15)
            if r.status_code == 200 and r.text.lstrip().startswith("{"):
                return r.text
        except httpx.HTTPError:
            continue
    return None


def _ler_cache(conn, chave: str) -> tuple[dict, bool] | None:
    """(resposta, ainda_valida) da celula, ou None se nunca foi buscada."""
    with conn.cursor() as cur:
        cur.execute(
            """SELECT resposta,
                      CASE WHEN buscado_em > SYSTIMESTAMP - NUMTODSINTERVAL(:dias, 'DAY')
                           THEN 1 ELSE 0 END AS valido
                 FROM cache_locais_osm WHERE celula = :c""",
            {"c": chave, "dias": VALIDADE_DIAS},
        )
        row = cur.fetchone()
    if not row:
        return None
    valor = row[0]
    # coluna "IS JSON": o driver pode entregar o objeto pronto, um CLOB ou texto
    if hasattr(valor, "read"):
        valor = valor.read()
    if isinstance(valor, (str, bytes)):
        valor = json.loads(valor)
    return valor, bool(row[1])


def _gravar_cache(conn, chave: str, texto: str) -> None:
    # atualiza se a celula ja existe; senao insere (o texto vai como CLOB, pode passar de 100 KB)
    with conn.cursor() as cur:
        cur.setinputsizes(r=oracledb.DB_TYPE_CLOB)
        cur.execute(
            "UPDATE cache_locais_osm SET resposta = :r, buscado_em = SYSTIMESTAMP WHERE celula = :c",
            {"c": chave, "r": texto},
        )
        if cur.rowcount == 0:
            cur.setinputsizes(r=oracledb.DB_TYPE_CLOB)
            cur.execute("INSERT INTO cache_locais_osm (celula, resposta) VALUES (:c, :r)", {"c": chave, "r": texto})


def locais_apoio(lat: float, lon: float) -> dict:
    """Resposta do Overpass para a regiao do ponto, usando o cache quando possivel.

    O campo "fonte" diz de onde veio: cache, openstreetmap ou cache_antigo
    (Overpass fora do ar, mas havia uma busca antiga guardada).
    """
    chave, clat, clon = celula(lat, lon)
    with db.transaction() as conn:
        cache = _ler_cache(conn, chave)
    if cache and cache[1]:
        return {"fonte": "cache", **cache[0]}

    # a conexao do banco nao fica presa enquanto espera o Overpass
    texto = _buscar_overpass(clat, clon)
    if texto:
        with db.transaction() as conn:
            _gravar_cache(conn, chave, texto)
        return {"fonte": "openstreetmap", **json.loads(texto)}
    if cache:
        return {"fonte": "cache_antigo", **cache[0]}
    return {"fonte": "indisponivel", "elements": []}

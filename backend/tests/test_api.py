"""Teste de integracao da API contra o Oracle real.

Rodar (com o Oracle no ar), dentro da pasta backend:
    python -m pytest -v
Os dados criados pelo teste (e-mails @teste-api.com) sao apagados no final.
"""
import pytest
from fastapi.testclient import TestClient

from app import db
from app.main import app

# PNG de 1x1 pixel valido
PNG = (b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00"
       b"\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\xf8\xff\xff?\x00\x05\xfe\x02\xfe\xa7\x9a\xa0\xa0"
       b"\x00\x00\x00\x00IEND\xaeB`\x82")

MOOCA = (-23.5590, -46.5990)


def _limpar():
    """Apaga tudo que os usuarios de teste criaram e recalcula o risco."""
    with db.transaction() as conn:
        with conn.cursor() as cur:
            ids = "(SELECT id_usuario FROM usuario WHERE email LIKE '%@teste-api.com')"
            cur.execute(f"DELETE FROM confirmacao_alagamento WHERE id_usuario IN {ids} "
                        f"OR id_alagamento IN (SELECT id_alagamento FROM alagamento WHERE id_usuario IN {ids})")
            cur.execute(f"DELETE FROM alagamento WHERE id_usuario IN {ids}")
            cur.execute(f"DELETE FROM pedido_ajuda WHERE id_usuario IN {ids}")
            cur.execute(f"DELETE FROM local_seguro WHERE id_usuario IN {ids}")  # avaliacoes caem em cascata
            cur.execute("DELETE FROM usuario WHERE email LIKE '%@teste-api.com'")
            cur.execute("BEGIN FOR b IN (SELECT id_bairro FROM bairro) LOOP "
                        "pkg_enchente.sp_recalcular_risco(b.id_bairro); END LOOP; END;")
            cur.execute("DELETE FROM historico_risco")


@pytest.fixture(scope="module")
def client():
    _limpar()
    with TestClient(app) as c:
        yield c
    _limpar()


def _cadastra(client, nome, email):
    r = client.post("/auth/register", json={
        "nome": nome, "email": email, "senha": "senha123",
        "latitude": MOOCA[0], "longitude": MOOCA[1]})
    assert r.status_code == 201, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def test_fluxo_completo(client):
    assert client.get("/health").json() == {"status": "ok"}

    # auth
    ana = _cadastra(client, "Ana Souza", "ana@teste-api.com")
    bruno = _cadastra(client, "Bruno Lima", "bruno@teste-api.com")
    assert client.post("/auth/register", json={
        "nome": "Outra", "email": "ana@teste-api.com", "senha": "senha123"}).status_code == 409
    assert client.post("/auth/login", json={"email": "ana@teste-api.com", "senha": "errada"}).status_code == 401
    assert client.post("/auth/login", json={"email": "ana@teste-api.com", "senha": "senha123"}).status_code == 200
    assert client.get("/alagamentos").status_code == 401
    assert client.get("/me", headers=ana).json()["bairro"] == "Mooca"

    # relato com foto
    r = client.post("/alagamentos", headers=ana,
                    data={"latitude": MOOCA[0], "longitude": MOOCA[1], "gravidade": 3, "descricao": "Rua alagada"},
                    files={"foto": ("foto.png", PNG, "image/png")})
    assert r.status_code == 201, r.text
    id_alag = r.json()["id_alagamento"]

    # foto invalida e relato duplicado
    assert client.post("/alagamentos", headers=ana,
                       data={"latitude": MOOCA[0], "longitude": MOOCA[1], "gravidade": 2},
                       files={"foto": ("x.png", b"nao e imagem", "image/png")}).status_code == 400
    assert client.post("/alagamentos", headers=ana,
                       data={"latitude": MOOCA[0], "longitude": MOOCA[1], "gravidade": 2}).status_code == 400

    # listagem
    lista = client.get("/alagamentos", headers=bruno,
                       params={"latitude": MOOCA[0], "longitude": MOOCA[1]}).json()
    item = next(a for a in lista if a["id_alagamento"] == id_alag)
    assert item["bairro"] == "Mooca" and item["autor"] == "Ana" and item["foto_url"]
    assert item["confirmacoes"] == 0 and item["meu"] is False

    # confirmacao: Bruno pode, duas vezes nao, Ana (autora) nao
    assert client.post(f"/alagamentos/{id_alag}/confirmar", headers=bruno).status_code == 200
    assert client.post(f"/alagamentos/{id_alag}/confirmar", headers=bruno).status_code == 409
    assert client.post(f"/alagamentos/{id_alag}/confirmar", headers=ana).status_code == 400
    assert client.post("/alagamentos/999999/confirmar", headers=bruno).status_code == 404

    # painel: risco da Mooca subiu (3 * 1,5 = 4,5 -> MODERADO)
    mooca = next(b for b in client.get("/bairros/indicadores", headers=ana).json() if b["nome"] == "Mooca")
    assert mooca["nivel_risco"] == "MODERADO" and mooca["alagamentos_ativos"] == 1

    # contatos + emergencia
    assert client.post("/contatos", headers=ana,
                       json={"nome": "Vovo", "telefone": "11999990000", "parentesco": "avo"}).status_code == 201
    e = client.post("/emergencia", headers=ana,
                    json={"tipo": "AJUDA", "latitude": MOOCA[0], "longitude": MOOCA[1], "mensagem": "Preciso de ajuda"})
    assert e.status_code == 201 and e.json()["contatos"][0]["nome"] == "Vovo"

    # Bruno (mesmo bairro) recebe a notificacao
    notifs = client.get("/notificacoes", headers=bruno).json()
    assert any(n["tipo"] == "AJUDA" for n in notifs)
    assert client.post("/notificacoes/lidas", headers=bruno).status_code == 200
    assert all(n["lida"] == "S" for n in client.get("/notificacoes", headers=bruno).json())

    # resumo pessoal e lista dos meus relatos (aba Conta)
    meu = client.get("/me/resumo", headers=ana).json()
    assert meu["relatos_total"] == 1 and meu["relatos_ativos"] == 1 and meu["confirmacoes_recebidas"] == 1
    assert client.get("/me/resumo", headers=bruno).json()["confirmacoes_dadas"] == 1
    relatos = client.get("/me/relatos", headers=ana).json()
    assert len(relatos) == 1 and relatos[0]["confirmacoes"] == 1 and relatos[0]["status"] == "ATIVO"

    # numeros gerais (view do Oracle)
    n = client.get("/dilu/numeros", headers=ana).json()
    assert n["relatos_total"] >= 1 and n["confirmacoes"] >= 1 and n["moradores"] >= 2
    assert n["pedidos_ajuda"] >= 1

    # resolver: so o dono
    assert client.post(f"/alagamentos/{id_alag}/resolver", headers=bruno).status_code == 403
    assert client.post(f"/alagamentos/{id_alag}/resolver", headers=ana).status_code == 200
    mooca = next(b for b in client.get("/bairros/indicadores", headers=ana).json() if b["nome"] == "Mooca")
    assert mooca["nivel_risco"] == "BAIXO"


def test_locais_seguros(client):
    """Locais seguros: cadastro com bairro e aviso aos vizinhos, sem repetir o ponto,
    votos (um por pessoa, pode mudar) e saida do mapa com 3 votos "nao e seguro"."""
    gabi = _cadastra(client, "Gabi Teste", "gabi@teste-api.com")
    vizinhos = [_cadastra(client, f"Vizinho {i}", f"viz{i}@teste-api.com") for i in range(3)]
    ponto = {"nome": "Estacionamento do mercado (piso 2)", "tipo": "PONTO_ALTO",
             "descricao": "Piso alto, a agua nunca chegou", "latitude": MOOCA[0] + 0.003, "longitude": MOOCA[1]}
    r = client.post("/locais-seguros", headers=gabi, json=ponto)
    assert r.status_code == 201, r.text
    id_local = r.json()["id_local"]
    # mesmo ponto (menos de 30 m) nao repete; tipo invalido e barrado
    assert client.post("/locais-seguros", headers=vizinhos[0], json={**ponto, "nome": "Outro"}).status_code == 409
    assert client.post("/locais-seguros", headers=gabi, json={**ponto, "tipo": "PRAIA"}).status_code == 422
    # vizinho do bairro foi avisado pelo trigger
    assert any(n["tipo"] == "LOCAL" for n in client.get("/notificacoes", headers=vizinhos[0]).json())

    perto = {"latitude": MOOCA[0], "longitude": MOOCA[1]}
    item = next(x for x in client.get("/locais-seguros", headers=vizinhos[0], params=perto).json() if x["id_local"] == id_local)
    assert item["bairro"] == "Mooca" and item["tipo"] == "PONTO_ALTO" and item["meu"] is False
    assert item["votos_seguro"] == 0 and item["meu_voto"] is None and item["distancia_km"] < 1
    assert client.get("/locais-seguros", headers=gabi, params={"latitude": -10, "longitude": -40}).json() == []  # longe

    # votos: dono nao vota; vizinho pode trocar o voto
    assert client.post(f"/locais-seguros/{id_local}/avaliar", headers=gabi, json={"seguro": True}).status_code == 409
    assert client.post(f"/locais-seguros/{id_local}/avaliar", headers=vizinhos[0], json={"seguro": True}).status_code == 200
    assert client.post(f"/locais-seguros/{id_local}/avaliar", headers=vizinhos[0], json={"seguro": False}).status_code == 200
    item = next(x for x in client.get("/locais-seguros", headers=vizinhos[0], params=perto).json() if x["id_local"] == id_local)
    assert item["votos_seguro"] == 0 and item["votos_inseguro"] == 1 and item["meu_voto"] == "N"

    # 3 "nao e seguro" e mais "nao" que "sim": sai do mapa
    for v in vizinhos[1:]:
        assert client.post(f"/locais-seguros/{id_local}/avaliar", headers=v, json={"seguro": False}).status_code == 200
    assert all(x["id_local"] != id_local for x in client.get("/locais-seguros", headers=gabi, params=perto).json())
    assert client.post(f"/locais-seguros/{id_local}/avaliar", headers=vizinhos[0], json={"seguro": True}).status_code == 404

    # remover: so quem cadastrou
    r = client.post("/locais-seguros", headers=gabi, json={**ponto, "tipo": "PONTO_ENCONTRO", "nome": "Praca alta"})
    id2 = r.json()["id_local"]
    assert client.delete(f"/locais-seguros/{id2}", headers=vizinhos[0]).status_code == 403
    assert client.delete(f"/locais-seguros/{id2}", headers=gabi).status_code == 200


def test_meus_lugares(client):
    """Lugares: salva com bairro descoberto pela PL/SQL, nao repete nome, limite de 5, remove so o proprio."""
    dani = _cadastra(client, "Dani Teste", "dani@teste-api.com")
    outro = _cadastra(client, "Edu Teste", "edu@teste-api.com")
    r = client.post("/lugares", headers=dani, json={"apelido": "Casa", "tipo": "CASA", "latitude": MOOCA[0], "longitude": MOOCA[1]})
    assert r.status_code == 201, r.text
    id_casa = r.json()["id_lugar"]
    assert client.post("/lugares", headers=dani, json={"apelido": "Casa", "latitude": 0, "longitude": 0}).status_code == 409
    assert client.post("/lugares", headers=dani, json={"apelido": "X", "tipo": "PRAIA", "latitude": 0, "longitude": 0}).status_code == 422
    lugares = client.get("/lugares", headers=dani).json()
    assert lugares == [{"id_lugar": id_casa, "apelido": "Casa", "tipo": "CASA", "latitude": MOOCA[0],
                        "longitude": MOOCA[1], "bairro": "Mooca"}]
    for i in range(4):
        assert client.post("/lugares", headers=dani, json={"apelido": f"L{i}", "latitude": -10, "longitude": -40}).status_code == 201
    assert client.post("/lugares", headers=dani, json={"apelido": "Sexto", "latitude": -10, "longitude": -40}).status_code == 409
    assert client.delete(f"/lugares/{id_casa}", headers=outro).status_code == 404
    assert client.delete(f"/lugares/{id_casa}", headers=dani).status_code == 200
    assert len(client.get("/lugares", headers=dani).json()) == 4


def test_emergencia_sem_gps_e_limite_de_login(client):
    """Pedido de ajuda sem GPS vale (bairro do cadastro, sem ponto inventado) e
    5 senhas erradas travam o login por alguns minutos."""
    from app.security import limite_login

    hugo = _cadastra(client, "Hugo Teste", "hugo@teste-api.com")
    r = client.post("/emergencia", headers=hugo, json={"tipo": "AJUDA"})
    assert r.status_code == 201, r.text
    assert r.json()["bairro"] == "Mooca" and r.json()["com_localizacao"] is False
    with db.transaction() as conn:
        p = db.query_one(conn, "SELECT latitude, longitude FROM pedido_ajuda WHERE id_pedido = :id",
                         {"id": r.json()["id_pedido"]})
    assert p["latitude"] is None and p["longitude"] is None
    # latitude sem longitude nao passa
    assert client.post("/emergencia", headers=hugo, json={"tipo": "AJUDA", "latitude": -23.5}).status_code == 422
    com_gps = client.post("/emergencia", headers=hugo,
                          json={"tipo": "SEGURO", "latitude": MOOCA[0], "longitude": MOOCA[1]}).json()
    assert com_gps["com_localizacao"] is True

    limite_login.limpar()
    errada = {"email": "hugo@teste-api.com", "senha": "errada"}
    certa = {"email": "hugo@teste-api.com", "senha": "senha123"}
    try:
        for _ in range(5):
            assert client.post("/auth/login", json=errada).status_code == 401
        assert client.post("/auth/login", json=errada).status_code == 429
        assert client.post("/auth/login", json=certa).status_code == 429  # travado mesmo com a senha certa
        # outro e-mail nao e afetado
        assert client.post("/auth/login", json={"email": "outro@teste-api.com", "senha": "x"}).status_code == 401
    finally:
        limite_login.limpar()
    assert client.post("/auth/login", json=certa).status_code == 200


def test_contato_repetido(client):
    """O mesmo telefone nao entra duas vezes nos contatos, mesmo escrito de outro jeito."""
    ivo = _cadastra(client, "Ivo Teste", "ivo@teste-api.com")
    assert client.post("/contatos", headers=ivo, json={"nome": "Mae", "telefone": "(11) 98888-7777"}).status_code == 201
    r = client.post("/contatos", headers=ivo, json={"nome": "Mae de novo", "telefone": "11 988887777"})
    assert r.status_code == 409 and "telefone" in r.json()["detail"]
    assert len(client.get("/contatos", headers=ivo).json()) == 1

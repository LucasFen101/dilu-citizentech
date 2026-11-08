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

    # abrigos ordenados por distancia
    abrigos = client.get("/abrigos", headers=ana, params={"latitude": MOOCA[0], "longitude": MOOCA[1]}).json()
    assert abrigos[0]["bairro"] == "Mooca"

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

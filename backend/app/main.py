"""API do Dilu (FastAPI).

Cada endpoint e uma casca fina: valida a entrada e chama a PL/SQL do Oracle
(package PKG_ENCHENTE), onde ficam as regras de negocio.
Rodar:  uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
Docs interativas: http://localhost:8000/docs
"""
import uuid
from contextlib import asynccontextmanager

import oracledb
from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from . import config, db
from .schemas import ContatoIn, EmergenciaIn, LoginIn, RegisterIn
from .security import create_token, current_user_id, hash_password, verify_password


@asynccontextmanager
async def lifespan(_: FastAPI):
    """Abre o pool ao iniciar e fecha ao desligar."""
    config.UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    db.init_pool()
    yield
    db.close_pool()


app = FastAPI(title="Dilu API", version="1.0.0", lifespan=lifespan)

# CORS aberto para o app Flutter (web) conseguir chamar a API em desenvolvimento.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

config.UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=config.UPLOAD_DIR), name="uploads")


# ------------------------------------------------------------------ erros
# Codigo ORA-20xxx da PL/SQL -> status HTTP
_STATUS_POR_CODIGO = {20001: 409, 20020: 404, 20021: 409, 20030: 403}


@app.exception_handler(oracledb.DatabaseError)
async def oracle_error_handler(_: Request, exc: oracledb.DatabaseError):
    """Converte erros de regra de negocio da PL/SQL em respostas HTTP claras."""
    parsed = db.parse_app_error(exc)
    if parsed:
        codigo, mensagem = parsed
        return JSONResponse(status_code=_STATUS_POR_CODIGO.get(codigo, 400), content={"detail": mensagem})
    return JSONResponse(status_code=500, content={"detail": "Erro interno no banco de dados."})


# ------------------------------------------------------------------ util
def _out_id(cur) -> "oracledb.Var":
    """Cria variavel de saida (OUT) numerica para as procedures."""
    return cur.var(oracledb.NUMBER)


def _assinatura_valida(data: bytes) -> bool:
    """Confere os primeiros bytes do arquivo (JPEG, PNG ou WEBP)."""
    return (
        data.startswith(b"\xff\xd8\xff")
        or data.startswith(b"\x89PNG\r\n\x1a\n")
        or (data[:4] == b"RIFF" and data[8:12] == b"WEBP")
    )


@app.get("/health", tags=["sistema"])
def health():
    """Verifica se a API e o banco estao no ar."""
    with db.transaction() as conn:
        db.query_one(conn, "SELECT 1 AS ok FROM dual")
    return {"status": "ok"}


# ------------------------------------------------------------------ auth
@app.post("/auth/register", status_code=201, tags=["auth"])
def register(body: RegisterIn):
    """Cadastra o usuario (senha com bcrypt) e ja devolve o token."""
    with db.transaction() as conn:
        with conn.cursor() as cur:
            out = _out_id(cur)
            cur.callproc(
                "pkg_enchente.sp_cadastrar_usuario",
                [body.nome, body.email, hash_password(body.senha), body.telefone,
                 body.latitude, body.longitude, out],
            )
            id_usuario = int(out.getvalue())
    return {"token": create_token(id_usuario), "id_usuario": id_usuario}


@app.post("/auth/login", tags=["auth"])
def login(body: LoginIn):
    """Valida e-mail/senha e devolve o token."""
    with db.transaction() as conn:
        user = db.query_one(
            conn,
            "SELECT id_usuario, senha_hash FROM usuario WHERE email = :email",
            {"email": body.email.lower()},
        )
    if not user or not verify_password(body.senha, user["senha_hash"]):
        raise HTTPException(status_code=401, detail="E-mail ou senha incorretos.")
    return {"token": create_token(user["id_usuario"]), "id_usuario": user["id_usuario"]}


@app.get("/me", tags=["auth"])
def me(uid: int = Depends(current_user_id)):
    """Dados do usuario logado."""
    with db.transaction() as conn:
        user = db.query_one(
            conn,
            """SELECT u.id_usuario, u.nome, u.email, u.telefone, b.nome AS bairro
                 FROM usuario u LEFT JOIN bairro b ON b.id_bairro = u.id_bairro
                WHERE u.id_usuario = :usr""",
            {"usr": uid},
        )
    if not user:
        raise HTTPException(status_code=401, detail="Usuario nao encontrado.")
    return user


@app.get("/me/resumo", tags=["auth"])
def meu_resumo(uid: int = Depends(current_user_id)):
    """Numeros pessoais do usuario (view VW_RESUMO_USUARIO): relatos, confirmacoes, pedidos de ajuda."""
    with db.transaction() as conn:
        resumo = db.query_one(
            conn,
            """SELECT relatos_total, relatos_ativos, relatos_resolvidos,
                      confirmacoes_recebidas, confirmacoes_dadas, pedidos_ajuda
                 FROM vw_resumo_usuario WHERE id_usuario = :usr""",
            {"usr": uid},
        )
    if not resumo:
        raise HTTPException(status_code=401, detail="Usuario nao encontrado.")
    return resumo


@app.get("/me/relatos", tags=["auth"])
def meus_relatos(uid: int = Depends(current_user_id)):
    """Alagamentos que o proprio usuario relatou (mais recentes primeiro)."""
    with db.transaction() as conn:
        return db.query(
            conn,
            """SELECT a.id_alagamento, a.gravidade, a.descricao, a.status, a.criado_em,
                      b.nome AS bairro,
                      (SELECT COUNT(*) FROM confirmacao_alagamento c
                        WHERE c.id_alagamento = a.id_alagamento) AS confirmacoes
                 FROM alagamento a LEFT JOIN bairro b ON b.id_bairro = a.id_bairro
                WHERE a.id_usuario = :usr
                ORDER BY a.criado_em DESC
                FETCH FIRST 50 ROWS ONLY""",
            {"usr": uid},
        )

# -------------------------------------------------------------- contatos
@app.get("/contatos", tags=["contatos"])
def listar_contatos(uid: int = Depends(current_user_id)):
    """Contatos de emergencia do usuario."""
    with db.transaction() as conn:
        return db.query(
            conn,
            """SELECT id_contato, nome, telefone, parentesco
                 FROM contato_emergencia WHERE id_usuario = :usr ORDER BY nome""",
            {"usr": uid},
        )


@app.post("/contatos", status_code=201, tags=["contatos"])
def criar_contato(body: ContatoIn, uid: int = Depends(current_user_id)):
    """Adiciona um contato de emergencia (maximo 5 por usuario)."""
    with db.transaction() as conn:
        total = db.query_one(
            conn, "SELECT COUNT(*) AS n FROM contato_emergencia WHERE id_usuario = :usr", {"usr": uid}
        )["n"]
        if total >= 5:
            raise HTTPException(status_code=400, detail="Limite de 5 contatos de emergencia.")
        with conn.cursor() as cur:
            novo = cur.var(oracledb.NUMBER)
            cur.execute(
                """INSERT INTO contato_emergencia (id_usuario, nome, telefone, parentesco)
                   VALUES (:usr, :nome, :tel, :par) RETURNING id_contato INTO :novo""",
                {"usr": uid, "nome": body.nome, "tel": body.telefone, "par": body.parentesco, "novo": novo},
            )
            return {"id_contato": int(novo.getvalue()[0])}


@app.delete("/contatos/{id_contato}", tags=["contatos"])
def remover_contato(id_contato: int, uid: int = Depends(current_user_id)):
    """Remove um contato do proprio usuario."""
    with db.transaction() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM contato_emergencia WHERE id_contato = :id AND id_usuario = :usr",
                {"id": id_contato, "usr": uid},
            )
            if cur.rowcount == 0:
                raise HTTPException(status_code=404, detail="Contato nao encontrado.")
    return {"ok": True}


# ----------------------------------------------------------- alagamentos
@app.get("/alagamentos", tags=["alagamentos"])
def listar_alagamentos(
    latitude: float | None = None,
    longitude: float | None = None,
    raio_km: float = 20,
    uid: int = Depends(current_user_id),
):
    """Alagamentos ativos. Com latitude/longitude, filtra pelo raio e informa a distancia."""
    binds: dict = {"usr": uid}
    dist_col = "NULL"
    filtro = ""
    if latitude is not None and longitude is not None:
        binds.update({"lat": latitude, "lon": longitude, "raio": raio_km})
        dist_col = "fn_distancia_km(a.latitude, a.longitude, :lat, :lon)"
        filtro = "AND fn_distancia_km(a.latitude, a.longitude, :lat, :lon) <= :raio"
    sql = f"""
        SELECT a.id_alagamento, a.latitude, a.longitude, a.descricao, a.gravidade,
               a.foto, a.criado_em, a.expira_em, a.id_usuario,
               b.nome AS bairro,
               SUBSTR(u.nome, 1, INSTR(u.nome || ' ', ' ') - 1) AS autor,
               (SELECT COUNT(*) FROM confirmacao_alagamento c
                 WHERE c.id_alagamento = a.id_alagamento) AS confirmacoes,
               (SELECT COUNT(*) FROM confirmacao_alagamento c
                 WHERE c.id_alagamento = a.id_alagamento AND c.id_usuario = :usr) AS confirmado_por_mim,
               {dist_col} AS distancia_km
          FROM alagamento a
          JOIN usuario u ON u.id_usuario = a.id_usuario
          LEFT JOIN bairro b ON b.id_bairro = a.id_bairro
         WHERE a.status = 'ATIVO' {filtro}
         ORDER BY a.criado_em DESC
         FETCH FIRST 200 ROWS ONLY"""
    with db.transaction() as conn:
        rows = db.query(conn, sql, binds)
    for r in rows:
        r["foto_url"] = f"/uploads/{r['foto']}" if r["foto"] else None
        r["meu"] = r["id_usuario"] == uid
        r["confirmado_por_mim"] = bool(r["confirmado_por_mim"])
        del r["id_usuario"], r["foto"]
    return rows


@app.post("/alagamentos", status_code=201, tags=["alagamentos"])
async def registrar_alagamento(
    latitude: float = Form(ge=-90, le=90),
    longitude: float = Form(ge=-180, le=180),
    gravidade: int = Form(ge=1, le=4),
    descricao: str | None = Form(default=None, max_length=500),
    foto: UploadFile | None = File(default=None),
    uid: int = Depends(current_user_id),
):
    """Registra um alagamento (foto opcional). A PL/SQL valida, acha o bairro e recalcula o risco."""
    nome_foto = None
    if foto is not None and foto.filename:
        if foto.content_type not in config.ALLOWED_IMAGE_TYPES:
            raise HTTPException(status_code=400, detail="Foto deve ser JPEG, PNG ou WEBP.")
        # le no maximo MAX+1 bytes: evita carregar arquivos gigantes na memoria
        dados = await foto.read(config.MAX_UPLOAD_BYTES + 1)
        if len(dados) > config.MAX_UPLOAD_BYTES:
            raise HTTPException(status_code=413, detail="Foto maior que 5 MB.")
        if not _assinatura_valida(dados):
            raise HTTPException(status_code=400, detail="Arquivo de imagem invalido.")
        nome_foto = f"{uuid.uuid4().hex}{config.ALLOWED_IMAGE_TYPES[foto.content_type]}"
        (config.UPLOAD_DIR / nome_foto).write_bytes(dados)

    try:
        with db.transaction() as conn:
            with conn.cursor() as cur:
                out = _out_id(cur)
                cur.callproc(
                    "pkg_enchente.sp_registrar_alagamento",
                    [uid, latitude, longitude, descricao, gravidade, nome_foto, out],
                )
                return {"id_alagamento": int(out.getvalue())}
    except Exception:
        if nome_foto:  # nao deixa foto orfa se o banco recusou o relato
            (config.UPLOAD_DIR / nome_foto).unlink(missing_ok=True)
        raise


@app.post("/alagamentos/{id_alagamento}/confirmar", tags=["alagamentos"])
def confirmar_alagamento(id_alagamento: int, uid: int = Depends(current_user_id)):
    """Confirma um relato da comunidade (aumenta o risco do bairro)."""
    with db.transaction() as conn:
        with conn.cursor() as cur:
            cur.callproc("pkg_enchente.sp_confirmar_alagamento", [id_alagamento, uid])
    return {"ok": True}


@app.post("/alagamentos/{id_alagamento}/resolver", tags=["alagamentos"])
def resolver_alagamento(id_alagamento: int, uid: int = Depends(current_user_id)):
    """Marca o proprio relato como resolvido."""
    with db.transaction() as conn:
        with conn.cursor() as cur:
            cur.callproc("pkg_enchente.sp_resolver_alagamento", [id_alagamento, uid])
    return {"ok": True}


# ------------------------------------------------------------ emergencia
@app.post("/emergencia", status_code=201, tags=["emergencia"])
def emergencia(body: EmergenciaIn, uid: int = Depends(current_user_id)):
    """'Preciso de ajuda' / 'Estou seguro'. Devolve os contatos para o app avisar por WhatsApp."""
    with db.transaction() as conn:
        with conn.cursor() as cur:
            out = _out_id(cur)
            cur.callproc(
                "pkg_enchente.sp_pedir_ajuda",
                [uid, body.latitude, body.longitude, body.tipo, body.mensagem, out],
            )
            id_pedido = int(out.getvalue())
        contatos = db.query(
            conn,
            "SELECT nome, telefone FROM contato_emergencia WHERE id_usuario = :usr",
            {"usr": uid},
        )
        usuario = db.query_one(conn, "SELECT nome FROM usuario WHERE id_usuario = :usr", {"usr": uid})
    return {"id_pedido": id_pedido, "contatos": contatos, "nome_usuario": usuario["nome"]}


# --------------------------------------------------------------- abrigos
@app.get("/abrigos", tags=["abrigos"])
def listar_abrigos(
    latitude: float | None = None,
    longitude: float | None = None,
    _: int = Depends(current_user_id),
):
    """Abrigos ativos, do mais proximo ao mais distante quando ha localizacao."""
    binds: dict = {}
    if latitude is not None and longitude is not None:
        binds = {"lat": latitude, "lon": longitude}
        dist = "fn_distancia_km(s.latitude, s.longitude, :lat, :lon)"
        ordem = "distancia_km"
    else:
        dist = "NULL"
        ordem = "s.nome"
    sql = f"""
        SELECT s.id_abrigo, s.nome, s.endereco, s.latitude, s.longitude, s.capacidade,
               s.telefone, b.nome AS bairro, {dist} AS distancia_km
          FROM abrigo s JOIN bairro b ON b.id_bairro = s.id_bairro
         WHERE s.ativo = 'S'
         ORDER BY {ordem}
         FETCH FIRST 100 ROWS ONLY"""
    with db.transaction() as conn:
        return db.query(conn, sql, binds)


# ------------------------------------------------------------ indicadores
@app.get("/bairros/indicadores", tags=["indicadores"])
def indicadores(_: int = Depends(current_user_id)):
    """Painel de risco por bairro (view VW_INDICADORES_BAIRRO), do mais ao menos arriscado."""
    with db.transaction() as conn:
        return db.query(
            conn,
            "SELECT * FROM vw_indicadores_bairro ORDER BY score_risco DESC, nome",
        )


@app.get("/bairros/{id_bairro}/historico", tags=["indicadores"])
def historico_bairro(id_bairro: int, _: int = Depends(current_user_id)):
    """Ultimas mudancas de nivel de risco do bairro."""
    with db.transaction() as conn:
        return db.query(
            conn,
            """SELECT score_risco, nivel_risco, registrado_em
                 FROM historico_risco WHERE id_bairro = :id
                ORDER BY registrado_em DESC FETCH FIRST 50 ROWS ONLY""",
            {"id": id_bairro},
        )


@app.get("/dilu/numeros", tags=["indicadores"])
def numeros(_: int = Depends(current_user_id)):
    """Numeros gerais do Dilu (view VW_DILU_NUMEROS): relatos, confirmacoes, pedidos atendidos..."""
    with db.transaction() as conn:
        return db.query_one(conn, "SELECT * FROM vw_dilu_numeros")


# ----------------------------------------------------------- notificacoes
@app.get("/notificacoes", tags=["notificacoes"])
def listar_notificacoes(uid: int = Depends(current_user_id)):
    """Notificacoes do usuario (mais recentes primeiro)."""
    with db.transaction() as conn:
        return db.query(
            conn,
            """SELECT id_notificacao, tipo, titulo, mensagem, lida, criado_em
                 FROM notificacao WHERE id_usuario = :usr
                ORDER BY criado_em DESC FETCH FIRST 100 ROWS ONLY""",
            {"usr": uid},
        )


@app.post("/notificacoes/lidas", tags=["notificacoes"])
def marcar_lidas(uid: int = Depends(current_user_id)):
    """Marca todas as notificacoes como lidas."""
    with db.transaction() as conn:
        with conn.cursor() as cur:
            cur.callproc("pkg_enchente.sp_marcar_notificacoes_lidas", [uid])
    return {"ok": True}

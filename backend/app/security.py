"""Senhas (bcrypt) e tokens JWT."""
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from . import config

_bearer = HTTPBearer(auto_error=False)


def hash_password(senha: str) -> str:
    """Gera o hash bcrypt (com salt) da senha."""
    return bcrypt.hashpw(senha.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(senha: str, senha_hash: str) -> bool:
    """Confere a senha digitada contra o hash salvo."""
    try:
        return bcrypt.checkpw(senha.encode("utf-8"), senha_hash.encode("utf-8"))
    except ValueError:
        return False


def create_token(id_usuario: int) -> str:
    """Cria um JWT com o id do usuario e validade de 7 dias."""
    payload = {
        "sub": str(id_usuario),
        "exp": datetime.now(timezone.utc) + timedelta(days=config.JWT_EXPIRE_DAYS),
    }
    return jwt.encode(payload, config.JWT_SECRET, algorithm=config.JWT_ALGORITHM)


def current_user_id(
    cred: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> int:
    """Dependencia: le o token do cabecalho Authorization e devolve o id do usuario."""
    if cred is None:
        raise HTTPException(status_code=401, detail="Faca login para continuar.")
    try:
        payload = jwt.decode(cred.credentials, config.JWT_SECRET, algorithms=[config.JWT_ALGORITHM])
        return int(payload["sub"])
    except (jwt.PyJWTError, KeyError, ValueError):
        raise HTTPException(status_code=401, detail="Sessao invalida ou expirada.")

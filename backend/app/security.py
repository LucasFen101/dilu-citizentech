"""Senhas (bcrypt), tokens JWT e limite de tentativas de login."""
import time
from collections import deque
from datetime import datetime, timedelta, timezone
from threading import Lock

import bcrypt
import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from . import config

_bearer = HTTPBearer(auto_error=False)


class LimiteTentativas:
    """Trava temporaria depois de varias senhas erradas (dificulta adivinhar senhas).

    Guarda em memoria so os horarios das falhas recentes de cada chave
    (e-mail + IP). Entradas antigas sao descartadas, entao a memoria nao cresce.
    """

    def __init__(self, maximo: int = 5, janela_segundos: int = 300, max_chaves: int = 5000):
        self.maximo = maximo
        self.janela = janela_segundos
        self.max_chaves = max_chaves
        self._falhas: dict[str, deque[float]] = {}
        self._trava = Lock()  # os endpoints rodam em varias threads

    def _recentes(self, chave: str, agora: float) -> deque[float]:
        fila = self._falhas.get(chave)
        if fila is None:
            return deque()
        while fila and agora - fila[0] > self.janela:
            fila.popleft()
        if not fila:
            del self._falhas[chave]
        return fila

    def bloqueado(self, chave: str) -> bool:
        with self._trava:
            return len(self._recentes(chave, time.monotonic())) >= self.maximo

    def registrar_falha(self, chave: str) -> None:
        with self._trava:
            agora = time.monotonic()
            if len(self._falhas) >= self.max_chaves:  # limpeza geral se alguem tentar encher a memoria
                for c in list(self._falhas):
                    self._recentes(c, agora)
            self._recentes(chave, agora)
            self._falhas.setdefault(chave, deque()).append(agora)

    def limpar(self, chave: str | None = None) -> None:
        with self._trava:
            if chave is None:
                self._falhas.clear()
            else:
                self._falhas.pop(chave, None)


# 5 senhas erradas em 5 minutos travam novas tentativas daquele e-mail naquele IP
limite_login = LimiteTentativas()


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
        raise HTTPException(status_code=401, detail="Faça login para continuar.")
    try:
        payload = jwt.decode(cred.credentials, config.JWT_SECRET, algorithms=[config.JWT_ALGORITHM])
        return int(payload["sub"])
    except (jwt.PyJWTError, KeyError, ValueError):
        raise HTTPException(status_code=401, detail="Sessão inválida ou expirada.")

"""Modelos de entrada (validacao automatica pelo Pydantic)."""
from typing import Literal

from pydantic import BaseModel, EmailStr, Field, model_validator


class RegisterIn(BaseModel):
    nome: str = Field(min_length=2, max_length=100)
    email: EmailStr
    senha: str = Field(min_length=6, max_length=72)  # bcrypt aceita ate 72 bytes
    telefone: str | None = Field(default=None, max_length=20)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)


class LoginIn(BaseModel):
    email: EmailStr
    senha: str = Field(min_length=1, max_length=72)


class ContatoIn(BaseModel):
    nome: str = Field(min_length=2, max_length=100)
    telefone: str = Field(min_length=8, max_length=20)
    parentesco: str | None = Field(default=None, max_length=40)


class LocalIn(BaseModel):
    """Local seguro cadastrado por um morador."""
    nome: str = Field(min_length=2, max_length=80)
    tipo: Literal["PONTO_ALTO", "ACOLHIMENTO", "PONTO_ENCONTRO", "DOACAO"]
    descricao: str | None = Field(default=None, max_length=300)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class AvaliacaoIn(BaseModel):
    """Voto do vizinho: o local e seguro ou nao."""
    seguro: bool


class LugarIn(BaseModel):
    """Lugar que o morador quer acompanhar (casa, trabalho, faculdade...)."""
    apelido: str = Field(min_length=1, max_length=40)
    tipo: Literal["CASA", "TRABALHO", "ESTUDO", "FAMILIA", "OUTRO"] = "OUTRO"
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class EmergenciaIn(BaseModel):
    """Pedido de ajuda / aviso de seguranca. A localizacao e opcional: sem GPS o
    pedido vale mesmo assim (o banco usa o bairro do cadastro), mas nunca vai um ponto inventado."""
    tipo: Literal["AJUDA", "SEGURO"]
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    mensagem: str | None = Field(default=None, max_length=300)

    @model_validator(mode="after")
    def _par_completo(self):
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError("Envie latitude e longitude juntas, ou nenhuma das duas.")
        return self

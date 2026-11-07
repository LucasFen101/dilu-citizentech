"""Modelos de entrada (validacao automatica pelo Pydantic)."""
from typing import Literal

from pydantic import BaseModel, EmailStr, Field


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


class EmergenciaIn(BaseModel):
    tipo: Literal["AJUDA", "SEGURO"]
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    mensagem: str | None = Field(default=None, max_length=300)

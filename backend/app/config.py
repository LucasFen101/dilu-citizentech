"""Configuracao da API. Valores podem ser trocados por variaveis de ambiente."""
import os
from pathlib import Path

ORACLE_USER = os.getenv("ORACLE_USER", "alerta")
ORACLE_PASSWORD = os.getenv("ORACLE_PASSWORD", "Alerta#2026")
ORACLE_DSN = os.getenv("ORACLE_DSN", "localhost:1521/XEPDB1")

# Segredo do JWT. Em producao, definir JWT_SECRET no ambiente.
JWT_SECRET = os.getenv("JWT_SECRET", "dev-secret-alerta-enchente-troque-em-producao")
JWT_ALGORITHM = "HS256"
JWT_EXPIRE_DAYS = 7

UPLOAD_DIR = Path(os.getenv("UPLOAD_DIR", Path(__file__).resolve().parent.parent / "uploads"))
MAX_UPLOAD_BYTES = 5 * 1024 * 1024  # 5 MB por foto
ALLOWED_IMAGE_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}

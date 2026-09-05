import json

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql://fashionstore:fashionstore@localhost:5433/fashionstore"
    jwt_secret: str = "dev-secret-change-me"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 8
    # Se lee como texto plano (no como JSON) para aceptar tanto '["https://a","https://b"]'
    # como 'https://a,https://b' desde la variable de entorno CORS_ORIGINS. Usar la property
    # cors_origins, no este campo.
    cors_origins_raw: str = Field("http://localhost:3000", alias="CORS_ORIGINS")
    frontend_url: str = "http://localhost:3000"

    stripe_secret_key: str = ""
    stripe_publishable_key: str = ""
    stripe_webhook_secret: str = ""

    @property
    def cors_origins(self) -> list[str]:
        texto = _sin_comillas(self.cors_origins_raw.strip())
        if not texto:
            return []
        if texto.startswith("["):
            return [_sin_comillas(o.strip()) for o in json.loads(texto)]
        return [_sin_comillas(o.strip()) for o in texto.split(",") if o.strip()]


def _sin_comillas(valor: str) -> str:
    if len(valor) >= 2 and valor[0] == valor[-1] and valor[0] in {'"', "'"}:
        return valor[1:-1]
    return valor


settings = Settings()

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

    # CU18 - asistente de chat (app/modules/asistente/). Sin ANTHROPIC_API_KEY el endpoint
    # devuelve 503 en vez de fallar todo el arranque del backend.
    anthropic_api_key: str = ""
    anthropic_model: str = "claude-haiku-4-5"

    # CU20 - delivery (app/core/ruteo.py). openrouteservice de HeiGIT: la API key del plan
    # gratuito se saca en https://openrouteservice.org/dev/#/signup sin tarjeta de credito.
    # Sin ORS_API_KEY el backend no se cae: cotiza con la distancia Haversine de respaldo y
    # marca la cotizacion como proveedor "HAVERSINE".
    ors_api_key: str = ""
    ors_base_url: str = "https://api.openrouteservice.org"
    ors_perfil: str = "driving-car"
    ors_timeout: float = 8.0

    # CU10 - subida de imagenes de catalogo (app/core/media.py). media_dir es relativo al
    # WORKDIR del contenedor (/app), montado como volumen en docker-compose para persistir
    # entre rebuilds; en Railway hace falta un Volume propio en la misma ruta.
    media_dir: str = "media"
    public_base_url: str = "http://localhost:8081"

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

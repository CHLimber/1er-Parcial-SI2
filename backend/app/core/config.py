import json
import logging
import os

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

    # Recuperacion de cuenta (POST /auth/recuperar). El enlace de un solo uso se manda por correo
    # SMTP (Gmail con contrasena de aplicacion, Brevo, etc.); con SMTP_HOST vacio no sale ningun
    # correo y el enlace queda en el log del backend. RECUPERACION_MOSTRAR_ENLACE=true lo devuelve
    # ademas en la respuesta (SOLO para demostrar sin correo: quien conozca un email podria tomar
    # esa cuenta, asi que en produccion va en false).
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from: str = ""
    smtp_starttls: bool = True
    # Resend (API HTTPS): tiene prioridad sobre SMTP y es lo que funciona en Railway. Sin dominio
    # verificado en Resend el remitente tiene que ser onboarding@resend.dev y solo deja enviar al
    # correo con el que se creo la cuenta de Resend.
    resend_api_key: str = ""
    resend_from: str = "FashionStore <onboarding@resend.dev>"
    # Push al celular (Firebase Cloud Messaging, API HTTP v1). Es el JSON de la cuenta de servicio
    # (Firebase -> Configuracion del proyecto -> Cuentas de servicio -> Generar clave nueva),
    # pegado en UNA linea, o en base64. Vacio = no sale ningun push y todo lo demas sigue igual.
    firebase_credenciales_json: str = ""
    # cada cuantos segundos el job de avisos (core/avisos.py) revisa correos y push pendientes
    avisos_intervalo_segundos: int = 10
    recuperacion_minutos: int = 30
    recuperacion_mostrar_enlace: bool = False

    stripe_secret_key: str = ""
    stripe_publishable_key: str = ""
    stripe_webhook_secret: str = ""

    # CU18 - asistente de chat (app/modules/relacion_con_la_clienta/asistente/). Sin ANTHROPIC_API_KEY el endpoint
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

    # CU04 E2 (app/core/jobs.py): cada cuantos segundos se llama a fn_expirar_reservas()
    # para liberar el stock comprometido por reservas vencidas. 120s alcanza de sobra frente
    # a los minutos que dura expira_en; bajarlo no libera "mas rapido" nada real, solo carga
    # mas seguido al pool.
    expirar_reservas_intervalo_segundos: int = 120

    # Multi-tenant: la tienda publica (catalogo, sucursales, asistente) es de UNA empresa. El
    # frontend la elige con el header X-Empresa (o ?empresa=slug); sin ninguno se usa esta.
    empresa_por_defecto: str = "fashionstore"

    # Copias de seguridad (app/modules/plataforma_saas/backups/). backups_dir es relativo al WORKDIR
    # del contenedor (/app), montado como volumen en docker-compose; en Railway hace falta un
    # Volume propio en esa ruta o las copias se pierden con cada redeploy. La copia automatica
    # (general de la plataforma) corre una vez al dia a backup_auto_hora, hora de Bolivia (UTC-4,
    # sin horario de verano) en formato HH:MM, y conserva las ultimas backup_auto_retencion; las
    # manuales (por empresa o general) conservan las ultimas backup_manual_retencion de cada alcance.
    backups_dir: str = "backups"
    backup_auto_activo: bool = True
    backup_auto_hora: str = "02:00"
    backup_auto_retencion: int = 7
    backup_manual_retencion: int = 10

    # Modulo G (app/modules/inteligencia_de_negocio/analitica/): donde se guardan los modelos entrenados (joblib).
    modelos_dir: str = "modelos_ml"

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


JWT_SECRET_DE_EJEMPLO = "dev-secret-change-me"


def verificar_jwt_secret(ajustes: "Settings") -> None:
    """Con el secreto de ejemplo cualquiera puede firmar un JWT de ADMIN. En Railway (que define
    RAILWAY_ENVIRONMENT en todos sus servicios) el arranque se corta; en local solo avisa, para
    no romper el `uvicorn --reload` de desarrollo."""
    if ajustes.jwt_secret and ajustes.jwt_secret != JWT_SECRET_DE_EJEMPLO:
        return
    if os.getenv("RAILWAY_ENVIRONMENT"):
        raise RuntimeError("JWT_SECRET no esta configurado: definilo en las variables de Railway")
    logging.getLogger(__name__).warning(
        "JWT_SECRET usa el valor de ejemplo: sirve solo para desarrollo local"
    )


settings = Settings()

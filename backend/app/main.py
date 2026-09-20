import mimetypes
import shutil
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.core.config import settings
from app.core.db import connect_pool, disconnect_pool
from app.modules.asistente.router import router as asistente_router
from app.modules.auditoria.router import router as auditoria_router
from app.modules.caja.router import router as caja_router
from app.modules.carrito.router import router as carrito_router
from app.modules.catalogo.admin_router import router as catalogo_admin_router
from app.modules.catalogo.router import router as catalogo_router
from app.modules.direcciones.router import router as direcciones_router
from app.modules.envios.admin_router import router as envios_admin_router
from app.modules.envios.router import router as envios_router
from app.modules.pagos.router import router as pagos_router
from app.modules.proveedores.router import router as proveedores_router
from app.modules.recepciones.router import router as recepciones_router
from app.modules.recomendaciones.router import router as recomendaciones_router
from app.modules.reportes.router import router as reportes_router
from app.modules.reservas.router import router as reservas_router
from app.modules.sucursales.admin_router import router as sucursales_admin_router
from app.modules.sucursales.router import router as sucursales_router
from app.modules.usuarios.admin_router import router as usuarios_admin_router
from app.modules.usuarios.router import router as usuarios_router
from app.modules.ventas.router import router as ventas_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    await connect_pool()
    yield
    await disconnect_pool()


app = FastAPI(title="FashionStore API", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# CU10: imagenes subidas por el panel de catalogo (ver app/core/media.py). Se crea la carpeta
# porque StaticFiles no monta un directorio inexistente.
Path(settings.media_dir).mkdir(parents=True, exist_ok=True)

# Imagenes "oficiales" versionadas en el repo (variantes de color generadas con IA, ver
# PENDIENTES.txt 2.9): se copian a MEDIA_DIR en cada arranque para que sobrevivan a un
# `docker compose down -v` (MEDIA_DIR es un volumen, media_semilla no). db/03_datos_iniciales.sql
# referencia estos archivos como http://localhost:8081/media/variantes/<archivo>.jpg.
_media_semilla = Path(__file__).resolve().parent / "media_semilla"
if _media_semilla.exists():
    shutil.copytree(_media_semilla, settings.media_dir, dirs_exist_ok=True)

# CU16: Python no conoce los formatos de realidad aumentada, asi que StaticFiles los serviria
# como text/plain y Google Scene Viewer / AR Quick Look rechazan el modelo. Hay que declararlos
# antes de montar /media.
mimetypes.add_type("model/gltf-binary", ".glb")
mimetypes.add_type("model/vnd.usdz+zip", ".usdz")

# /media va con CORS abierto, aparte del CORSMiddleware de la API. Son archivos publicos
# (fotos de catalogo y modelos 3D) que se piden sin token, y el visor 3D de CU16 los trae con
# `fetch` desde el WebView de la app movil, cuyo origen es un `http://127.0.0.1:<puerto
# aleatorio>` que no se puede listar en CORS_ORIGINS. Sin esta cabecera el navegador descarta
# el GLB y el visor queda en blanco. Se envuelve solo el StaticFiles, asi la API sigue con su
# lista blanca de origenes y con allow_credentials.
app.mount(
    "/media",
    CORSMiddleware(
        StaticFiles(directory=settings.media_dir),
        allow_origins=["*"],
        allow_methods=["GET", "HEAD"],
        allow_headers=["*"],
    ),
    name="media",
)

app.include_router(usuarios_router)
app.include_router(catalogo_router)
app.include_router(sucursales_router)
app.include_router(reservas_router)
app.include_router(carrito_router)
app.include_router(ventas_router)
app.include_router(pagos_router)
app.include_router(caja_router)
app.include_router(proveedores_router)
app.include_router(recepciones_router)
app.include_router(catalogo_admin_router)
app.include_router(sucursales_admin_router)
app.include_router(usuarios_admin_router)
app.include_router(reportes_router)
app.include_router(recomendaciones_router)
app.include_router(asistente_router)
app.include_router(auditoria_router)
app.include_router(direcciones_router)
app.include_router(envios_router)
app.include_router(envios_admin_router)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}

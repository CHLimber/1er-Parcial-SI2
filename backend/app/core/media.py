"""Almacenamiento local de imagenes subidas desde el panel de administracion (CU10).

Los archivos quedan bajo `settings.media_dir` (por defecto `media/`, montado como volumen en
docker-compose para que sobreviva a un rebuild) y se sirven como estaticos desde `/media` (ver
app/main.py). La URL que termina en `producto_imagen.url` es siempre absoluta
(`settings.public_base_url` + `/media/...`), igual que si fuera un link externo tipo picsum.photos
del seed -- asi el resto del sistema (frontend, movil, admin_router) no distingue una imagen
subida de una pegada a mano.
"""

import uuid
from pathlib import Path
from uuid import UUID

from fastapi import HTTPException, UploadFile, status

from app.core.config import settings

EXTENSIONES_POR_CONTENT_TYPE = {"image/jpeg": "jpg", "image/png": "png"}
TAMANIO_MAXIMO_BYTES = 5 * 1024 * 1024  # 5 MB

MEDIA_ROOT = Path(settings.media_dir)


async def guardar_imagen_producto(producto_id: UUID, archivo: UploadFile) -> tuple[str, str]:
    """Valida y guarda el archivo en disco. Devuelve (url_publica, formato) listos para
    insertar en producto_imagen."""
    extension = EXTENSIONES_POR_CONTENT_TYPE.get(archivo.content_type or "")
    if extension is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Solo se aceptan imagenes JPG o PNG",
        )

    contenido = await archivo.read()
    if not contenido:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="El archivo esta vacio")
    if len(contenido) > TAMANIO_MAXIMO_BYTES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="La imagen no puede superar los 5 MB",
        )

    carpeta = MEDIA_ROOT / "productos" / str(producto_id)
    carpeta.mkdir(parents=True, exist_ok=True)
    nombre_archivo = f"{uuid.uuid4()}.{extension}"
    (carpeta / nombre_archivo).write_bytes(contenido)

    url = f"{settings.public_base_url}/media/productos/{producto_id}/{nombre_archivo}"
    return url, extension.upper()


def eliminar_si_es_local(url: str) -> None:
    """Borra del disco el archivo detras de una URL de /media. Una URL externa (las de
    picsum.photos del seed, o una pegada a mano) no toca el filesystem."""
    prefijo = f"{settings.public_base_url}/media/"
    if not url.startswith(prefijo):
        return
    ruta = MEDIA_ROOT / url[len(prefijo):]
    try:
        ruta.unlink(missing_ok=True)
    except OSError:
        pass

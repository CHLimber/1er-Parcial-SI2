import logging
import math
from datetime import datetime, timezone

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.auditoria import registrar_auditoria
from app.core.config import settings
from app.core.correo import enviar_correo
from app.core.db import get_connection
from app.core.deps import exigir_empresa_operativa, get_current_usuario, obtener_permisos
from app.core.plan import funciones_habilitadas, plan_de_empresa
from app.core.security import create_access_token, hash_password, verify_password
from app.modules.acceso_y_organizacion.usuarios.recuperacion import (
    crear_token_recuperacion,
    huella_coincide,
    leer_token_recuperacion,
)
from app.modules.acceso_y_organizacion.usuarios.schemas import (
    CambiarPasswordRequest,
    LoginRequest,
    RecuperarPasswordRequest,
    RecuperarPasswordResponse,
    RegistroRequest,
    RestablecerPasswordRequest,
    TokenResponse,
    UsuarioOut,
)

router = APIRouter(prefix="/auth", tags=["usuarios"])
log = logging.getLogger(__name__)

MENSAJE_RECUPERACION = (
    "Si el correo corresponde a una cuenta, te enviamos un enlace para elegir una contrasena nueva. "
    "El enlace vence en {minutos} minutos y sirve una sola vez."
)

_MAX_INTENTOS_DEFECTO = 5
_BLOQUEO_MINUTOS_DEFECTO = 15


async def _politica_intentos(conn: asyncpg.Connection) -> tuple[int, int]:
    """Intentos maximos y minutos de bloqueo, parametrizables sin redesplegar (tabla
    `configuracion`, mismo patron que `reserva_horas_vigencia`)."""
    filas = await conn.fetch(
        "SELECT clave, valor FROM configuracion WHERE clave IN ('login_max_intentos', 'login_bloqueo_minutos')"
    )
    valores = {fila["clave"]: fila["valor"] for fila in filas}
    max_intentos = int(valores.get("login_max_intentos", _MAX_INTENTOS_DEFECTO))
    bloqueo_minutos = int(valores.get("login_bloqueo_minutos", _BLOQUEO_MINUTOS_DEFECTO))
    return max_intentos, bloqueo_minutos


async def _armar_usuario(conn: asyncpg.Connection, fila: asyncpg.Record) -> UsuarioOut:
    """UsuarioOut con permisos y datos del tenant (empresa y plan)."""
    plan = await plan_de_empresa(conn, fila["empresa_id"]) if fila["empresa_id"] else None
    return UsuarioOut(
        id=fila["id"],
        email=fila["email"],
        nombre=fila["nombre"],
        apellido=fila["apellido"],
        tipo=fila["tipo"],
        rol=fila["rol"],
        cargo=fila["cargo"],
        permisos=await obtener_permisos(conn, fila["id"]),
        empresa_id=fila["empresa_id"],
        empresa=fila["empresa"],
        empresa_slug=fila["empresa_slug"],
        plan=plan["plan_nombre"] if plan else None,
        funciones_plan=funciones_habilitadas(plan),
    )


@router.post("/registro", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def registro(
    body: RegistroRequest,
    conn: asyncpg.Connection = Depends(get_connection),
) -> TokenResponse:
    """CU02 - Registrarse. Solo crea cuentas de tipo CLIENTE: el alta de personal es
    responsabilidad del administrador (CU13)."""
    try:
        async with conn.transaction():
            row = await conn.fetchrow(
                """
                INSERT INTO usuario (email, password_hash, nombre, apellido, telefono, tipo)
                VALUES ($1, $2, $3, $4, $5, 'CLIENTE')
                RETURNING id, email, nombre, apellido, tipo
                """,
                body.email,
                hash_password(body.password),
                body.nombre,
                body.apellido,
                body.telefono,
            )
            # el perfil nace vacio: es lo que despues alimenta al recomendador
            await conn.execute(
                "INSERT INTO perfil_cliente (usuario_id, fecha_nacimiento, acepta_marketing) VALUES ($1, $2, $3)",
                row["id"],
                body.fecha_nacimiento,
                body.acepta_marketing,
            )
            await registrar_auditoria(
                conn,
                usuario_id=row["id"],
                entidad="usuario",
                entidad_id=row["id"],
                accion="CREAR",
                datos_despues={"email": row["email"], "tipo": "CLIENTE"},
            )
    except asyncpg.UniqueViolationError:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Ese correo ya esta registrado")

    usuario = UsuarioOut(
        id=row["id"],
        email=row["email"],
        nombre=row["nombre"],
        apellido=row["apellido"],
        tipo=row["tipo"],
        rol=None,
        permisos=[],
    )
    token = create_access_token(subject=str(row["id"]), extra_claims={"tipo": row["tipo"]})
    return TokenResponse(access_token=token, usuario=usuario)


@router.post("/login", response_model=TokenResponse)
async def login(
    body: LoginRequest,
    conn: asyncpg.Connection = Depends(get_connection),
) -> TokenResponse:
    row = await conn.fetchrow(
        """
        SELECT u.id, u.email, u.password_hash, u.nombre, u.apellido, u.tipo,
               u.activo, u.intentos_fallidos, u.bloqueado_hasta, r.nombre AS rol, e.cargo,
               u.empresa_id, em.nombre AS empresa, em.slug AS empresa_slug,
               em.activa AS empresa_activa
        FROM usuario u
        LEFT JOIN rol r      ON r.id = u.rol_id
        LEFT JOIN empleado e ON e.usuario_id = u.id AND e.activo
        LEFT JOIN empresa em ON em.id = u.empresa_id
        WHERE u.email = $1
        """,
        body.email,
    )

    credenciales_invalidas = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED, detail="Email o contrasena invalidos"
    )

    if row is None or not row["activo"]:
        raise credenciales_invalidas

    ahora = datetime.now(timezone.utc)
    if row["bloqueado_hasta"] is not None and row["bloqueado_hasta"] > ahora:
        minutos_restantes = math.ceil((row["bloqueado_hasta"] - ahora).total_seconds() / 60)
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                f"Cuenta bloqueada por demasiados intentos fallidos. "
                f"Volve a intentar en {minutos_restantes} minuto(s)."
            ),
        )

    if not verify_password(body.password, row["password_hash"]):
        max_intentos, bloqueo_minutos = await _politica_intentos(conn)
        intentos = row["intentos_fallidos"] + 1

        if intentos >= max_intentos:
            await conn.execute(
                """
                UPDATE usuario
                   SET intentos_fallidos = 0,
                       bloqueado_hasta   = now() + make_interval(mins => $2)
                 WHERE id = $1
                """,
                row["id"],
                bloqueo_minutos,
            )
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=(
                    f"Demasiados intentos fallidos. Tu cuenta quedo bloqueada por "
                    f"{bloqueo_minutos} minuto(s)."
                ),
            )

        await conn.execute(
            "UPDATE usuario SET intentos_fallidos = $2 WHERE id = $1", row["id"], intentos
        )
        restantes = max_intentos - intentos
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=(
                f"Email o contrasena invalidos. Te queda(n) {restantes} intento(s) "
                "antes de que se bloquee la cuenta."
            ),
        )

    # empresa suspendida (todos afuera) o suscripcion vencida (solo entra el ADMIN a renovar)
    await exigir_empresa_operativa(conn, row["id"], row["empresa_id"])

    await conn.execute(
        "UPDATE usuario SET ultimo_acceso = now(), intentos_fallidos = 0, bloqueado_hasta = NULL WHERE id = $1",
        row["id"],
    )
    await registrar_auditoria(
        conn,
        usuario_id=row["id"],
        entidad="usuario",
        entidad_id=row["id"],
        accion="LOGIN",
    )

    usuario = await _armar_usuario(conn, row)
    token = create_access_token(subject=str(row["id"]), extra_claims={"tipo": row["tipo"]})
    return TokenResponse(access_token=token, usuario=usuario)


@router.get("/yo", response_model=UsuarioOut)
async def usuario_actual(
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> UsuarioOut:
    """Rehidrata la sesion guardada en el navegador: si el administrador cambio el rol o los
    permisos del usuario (CU13), el frontend se entera al recargar."""
    fila = await conn.fetchrow(
        """
        SELECT u.id, u.email, u.nombre, u.apellido, u.tipo, r.nombre AS rol, e.cargo,
               u.empresa_id, em.nombre AS empresa, em.slug AS empresa_slug
        FROM usuario u
        LEFT JOIN rol r      ON r.id = u.rol_id
        LEFT JOIN empleado e ON e.usuario_id = u.id AND e.activo
        LEFT JOIN empresa em ON em.id = u.empresa_id
        WHERE u.id = $1
        """,
        usuario["id"],
    )
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Usuario no encontrado")

    # al recargar la pagina, quien ya no puede operar (empresa suspendida o suscripcion vencida)
    # sale de la sesion en vez de quedar adentro con todo respondiendo 402/403
    await exigir_empresa_operativa(conn, fila["id"], fila["empresa_id"])

    return await _armar_usuario(conn, fila)


@router.post("/password", status_code=status.HTTP_204_NO_CONTENT)
async def cambiar_password(
    body: CambiarPasswordRequest,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> None:
    """Cambiar mi propia contrasena: CLIENTE o STAFF, cualquiera logueado. CU13 (mas arriba
    en este mismo archivo el bloque de /admin) resetea la de otro sin conocerla; aca se
    exige la actual para no dejar que quien te robe la sesion te cambie la contrasena."""
    fila = await conn.fetchrow("SELECT password_hash FROM usuario WHERE id = $1", usuario["id"])
    if fila is None or not verify_password(body.password_actual, fila["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="La contrasena actual no es correcta"
        )
    if body.password_nueva == body.password_actual:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="La contrasena nueva no puede ser igual a la actual",
        )

    async with conn.transaction():
        await conn.execute(
            "UPDATE usuario SET password_hash = $2 WHERE id = $1",
            usuario["id"],
            hash_password(body.password_nueva),
        )
        # nunca se guarda el hash en la auditoria, solo que el cambio ocurrio
        await registrar_auditoria(
            conn,
            usuario_id=usuario["id"],
            entidad="usuario",
            entidad_id=usuario["id"],
            accion="ACTUALIZAR",
            datos_despues={"password": "cambiada por el propio usuario"},
        )


@router.post("/recuperar", response_model=RecuperarPasswordResponse)
async def recuperar_password(
    body: RecuperarPasswordRequest,
    conn: asyncpg.Connection = Depends(get_connection),
) -> RecuperarPasswordResponse:
    """Recuperacion de cuenta, paso 1: pide el enlace. Publico, para CLIENTE y STAFF. La
    respuesta es la misma exista o no el correo, para no revelar quien tiene cuenta. Una cuenta
    desactivada o de una empresa suspendida tampoco recibe enlace."""
    respuesta = RecuperarPasswordResponse(
        mensaje=MENSAJE_RECUPERACION.format(minutos=settings.recuperacion_minutos)
    )
    fila = await conn.fetchrow(
        """
        SELECT u.id, u.email, u.nombre, u.password_hash
          FROM usuario u
          LEFT JOIN empresa em ON em.id = u.empresa_id
         WHERE u.email = $1 AND u.activo AND (u.empresa_id IS NULL OR em.activa)
        """,
        body.email,
    )
    if fila is None:
        return respuesta

    token = crear_token_recuperacion(str(fila["id"]), fila["password_hash"])
    enlace = f"{settings.frontend_url.rstrip('/')}/restablecer-password?token={token}"
    enviado = await enviar_correo(
        fila["email"],
        "Recupera tu contrasena de FashionStore",
        (
            f"Hola {fila['nombre']},\n\n"
            "Recibimos un pedido para elegir una contrasena nueva en tu cuenta de FashionStore.\n"
            f"Entra a este enlace (vence en {settings.recuperacion_minutos} minutos y sirve una sola vez):\n\n"
            f"{enlace}\n\n"
            "Si no fuiste vos, ignora este correo: tu contrasena actual sigue funcionando."
        ),
    )
    if not enviado:
        # sin SMTP (o si fallo) el enlace queda en el log del backend para quien opera el sistema
        log.warning("Recuperacion de contrasena para %s (correo no enviado): %s", fila["email"], enlace)
    await registrar_auditoria(
        conn,
        usuario_id=fila["id"],
        entidad="usuario",
        entidad_id=fila["id"],
        accion="ACTUALIZAR",
        datos_despues={"recuperacion": "enlace solicitado", "correo_enviado": enviado},
    )
    if settings.recuperacion_mostrar_enlace:
        respuesta.enlace = enlace
    return respuesta


@router.post("/restablecer", status_code=status.HTTP_204_NO_CONTENT)
async def restablecer_password(
    body: RestablecerPasswordRequest,
    conn: asyncpg.Connection = Depends(get_connection),
) -> None:
    """Recuperacion de cuenta, paso 2: con el enlace elige la contrasena nueva. Tambien levanta
    el bloqueo por intentos, porque quien olvido su contrasena casi seguro lo agoto."""
    enlace_invalido = HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail="El enlace no es valido o ya vencio: pedi uno nuevo desde 'Olvide mi contrasena'",
    )
    datos = leer_token_recuperacion(body.token)
    if datos is None:
        raise enlace_invalido
    usuario_id, huella = datos

    fila = await conn.fetchrow(
        "SELECT id, password_hash, activo FROM usuario WHERE id = $1::uuid", usuario_id
    )
    # la huella cambia con la contrasena: un enlace ya usado (o de una contrasena anterior) no sirve
    if fila is None or not fila["activo"] or not huella_coincide(fila["password_hash"], huella):
        raise enlace_invalido
    if verify_password(body.password_nueva, fila["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="La contrasena nueva no puede ser igual a la actual",
        )

    async with conn.transaction():
        await conn.execute(
            """
            UPDATE usuario SET password_hash = $2, intentos_fallidos = 0, bloqueado_hasta = NULL
             WHERE id = $1
            """,
            fila["id"],
            hash_password(body.password_nueva),
        )
        await registrar_auditoria(
            conn,
            usuario_id=fila["id"],
            entidad="usuario",
            entidad_id=fila["id"],
            accion="ACTUALIZAR",
            datos_despues={"password": "restablecida con el enlace de recuperacion"},
        )

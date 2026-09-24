import math
from datetime import datetime, timezone

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import get_current_usuario, obtener_permisos
from app.core.security import create_access_token, hash_password, verify_password
from app.modules.usuarios.schemas import (
    CambiarPasswordRequest,
    LoginRequest,
    RegistroRequest,
    TokenResponse,
    UsuarioOut,
)

router = APIRouter(prefix="/auth", tags=["usuarios"])

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
               u.activo, u.intentos_fallidos, u.bloqueado_hasta, r.nombre AS rol, e.cargo
        FROM usuario u
        LEFT JOIN rol r      ON r.id = u.rol_id
        LEFT JOIN empleado e ON e.usuario_id = u.id AND e.activo
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

    usuario = UsuarioOut(
        id=row["id"],
        email=row["email"],
        nombre=row["nombre"],
        apellido=row["apellido"],
        tipo=row["tipo"],
        rol=row["rol"],
        cargo=row["cargo"],
        permisos=await obtener_permisos(conn, row["id"]),
    )
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
        SELECT u.id, u.email, u.nombre, u.apellido, u.tipo, r.nombre AS rol, e.cargo
        FROM usuario u
        LEFT JOIN rol r      ON r.id = u.rol_id
        LEFT JOIN empleado e ON e.usuario_id = u.id AND e.activo
        WHERE u.id = $1
        """,
        usuario["id"],
    )
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Usuario no encontrado")

    return UsuarioOut(
        id=fila["id"],
        email=fila["email"],
        nombre=fila["nombre"],
        apellido=fila["apellido"],
        tipo=fila["tipo"],
        rol=fila["rol"],
        cargo=fila["cargo"],
        permisos=await obtener_permisos(conn, fila["id"]),
    )


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

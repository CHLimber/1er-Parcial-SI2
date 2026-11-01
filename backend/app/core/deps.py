import asyncpg
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.db import get_connection
from app.core.security import decode_access_token

bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_usuario(
    credenciales: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    conn: asyncpg.Connection = Depends(get_connection),
) -> dict:
    sesion_invalida = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED, detail="Sesion invalida o expirada"
    )
    if credenciales is None:
        raise sesion_invalida

    payload = decode_access_token(credenciales.credentials)
    if payload is None or "sub" not in payload:
        raise sesion_invalida
    # los tokens de un solo uso (recuperar contrasena) llevan `uso` y no abren una sesion
    if "uso" in payload:
        raise sesion_invalida

    fila = await conn.fetchrow(
        "SELECT id, tipo, activo, empresa_id FROM usuario WHERE id = $1::uuid",
        payload["sub"],
    )
    if fila is None or not fila["activo"]:
        raise sesion_invalida

    return {"id": fila["id"], "tipo": fila["tipo"], "empresa_id": fila["empresa_id"]}


# Multi-tenant (segundo parcial): el personal pertenece a una EMPRESA (usuario.empresa_id) y
# todo lo que toca tiene que ser de esa empresa. Este modulo solo arma la identidad
# {id, rol, empresa_id, sucursal_id, cargo, permisos}; el recorte por tenant de cada consulta
# lo hacen los routers con app/core/tenant.py. Una empresa suspendida (empresa.activa = FALSE)
# deja a todo su personal afuera con 403.
#
# CU07 y CU08 autorizan por PERMISO (PENDIENTES 3.1), igual que el resto del sistema: el cargo
# ya no decide quien opera. Ademas del permiso exigen una fila activa en `empleado`, porque
# caja y reservas son operaciones DE UNA SUCURSAL y los routers necesitan su sucursal_id.
#   - Caja (CU07, /caja/* y /ventas/pos): permiso `caja.crear` (operar la caja: abrir sesion,
#     cobrar, verificar pagos QR/efectivo, cerrar). Lo tienen CAJERO, ENCARGADO y ADMIN.
#   - Reservas (CU08, /reservas/sucursal y confirmar/rechazar/preparar/...): permiso
#     `reservas.actualizar`. Lo tienen ENCARGADO, CAJERO y ADMIN.
# Decision: el ADMIN puede operar caja y reservas, pero solo las de la sucursal de su propia
# fila de empleado. Un ADMIN sin fila de empleado recibe 403: no hay una sucursal "por
# defecto" sobre la que operar.
# Los destinatarios de notificaciones (reservas/router.py, pagos/servicio.py) se siguen
# eligiendo por cargo ENCARGADO/CAJERO: eso dice QUIEN es la persona, no QUE puede hacer.


# Cabecera con el motivo de un bloqueo de empresa. Web y movil la leen para cerrar la sesion y
# mostrar un aviso propio en el login en vez de un error generico (CORS la expone en main.py).
MOTIVO_EMPRESA_SUSPENDIDA = "EMPRESA_SUSPENDIDA"
MOTIVO_SUSCRIPCION_VENCIDA = "SUSCRIPCION_VENCIDA"

# Lo unico que el personal sin rol ADMIN puede tocar con la suscripcion vencida: sincronizar lo
# que registro sin conexion ANTES del vencimiento (el backend decide operacion por operacion).
RUTAS_SIN_BLOQUEO_POR_VENCIMIENTO = ("/sync",)


_VIGENTE = "(su.id IS NOT NULL AND su.estado IN ('PRUEBA', 'ACTIVA') AND su.vence_en > now())"

# Lo que hace falta saber del personal en CADA request, en una sola consulta (antes eran cuatro:
# el usuario y su rol, si la empresa puede operar, los permisos del rol y la suscripcion con su
# plan). `su`/`pl` salen del mismo JOIN que decide la vigencia, y las columnas del plan son las
# que lee core/plan.py::evaluar_acceso, asi requiere_funcion_plan no vuelve a consultarlo.
_SQL_PERSONAL = f"""
SELECT u.id, u.empresa_id, r.nombre AS rol, e.sucursal_id, e.cargo,
       em.activa, {_VIGENTE} AS vigente,
       COALESCE(ARRAY(
           SELECT p.codigo::text
             FROM rol_permiso rp JOIN permiso p ON p.id = rp.permiso_id
            WHERE rp.rol_id = u.rol_id
            ORDER BY p.codigo), ARRAY[]::text[]) AS permisos,
       su.id AS suscripcion_id, su.estado::text AS estado, su.vence_en, su.inicio,
       pl.nombre AS plan_nombre, pl.perfiles_clientes, pl.traspasos, pl.operacion_offline,
       pl.reportes, pl.ia_reportes, pl.analitica_ml
  FROM usuario u
  LEFT JOIN rol r          ON r.id = u.rol_id
  LEFT JOIN empleado e     ON e.usuario_id = u.id AND e.activo
  LEFT JOIN empresa em     ON em.id = u.empresa_id
  LEFT JOIN suscripcion su ON su.empresa_id = u.empresa_id
  LEFT JOIN plan pl        ON pl.id = su.plan_id
 WHERE u.id = $1
"""

# Igual para CU07/CU08 (caja y reservas): ademas la sucursal del empleado tiene que ser de su
# misma empresa (si alguien la movio de empresa a mano, el empleado deja de operar ahi).
_SQL_EMPLEADO_OPERATIVO = f"""
SELECT u.empresa_id, r.nombre AS rol, e.sucursal_id, em.activa, {_VIGENTE} AS vigente,
       COALESCE(e.usuario_id IS NOT NULL AND s.empresa_id = u.empresa_id, FALSE) AS sucursal_propia,
       COALESCE(ARRAY(
           SELECT p.codigo::text
             FROM rol_permiso rp JOIN permiso p ON p.id = rp.permiso_id
            WHERE rp.rol_id = u.rol_id
            ORDER BY p.codigo), ARRAY[]::text[]) AS permisos
  FROM usuario u
  LEFT JOIN rol r          ON r.id = u.rol_id
  LEFT JOIN empleado e     ON e.usuario_id = u.id AND e.activo
  LEFT JOIN sucursal s     ON s.id = e.sucursal_id
  LEFT JOIN empresa em     ON em.id = u.empresa_id
  LEFT JOIN suscripcion su ON su.empresa_id = u.empresa_id
 WHERE u.id = $1
"""


def _evaluar_empresa(activa, vigente, rol, ruta: str | None) -> None:
    """Decide si el personal de una empresa puede operar (funcion pura: la usan
    exigir_empresa_operativa y las dependencias que ya leyeron estos datos en su consulta)."""
    if not activa:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu empresa esta suspendida en la plataforma: contacta a soporte",
            headers={"X-Motivo": MOTIVO_EMPRESA_SUSPENDIDA},
        )
    if vigente or rol == "ADMIN":
        return
    if ruta is not None and ruta.startswith(RUTAS_SIN_BLOQUEO_POR_VENCIMIENTO):
        return
    raise HTTPException(
        status_code=status.HTTP_402_PAYMENT_REQUIRED,
        detail=(
            "La suscripcion de tu empresa vencio y por eso no podes usar la plataforma. "
            "Avisale al administrador de tu empresa para que la renueve"
        ),
        headers={"X-Motivo": MOTIVO_SUSCRIPCION_VENCIDA},
    )


async def exigir_empresa_operativa(
    conn: asyncpg.Connection, usuario_id, empresa_id, ruta: str | None = None
) -> None:
    """Corta al personal de una empresa que no puede operar.

    - Empresa suspendida (empresa.activa = FALSE): nadie de la empresa entra (403).
    - Suscripcion vencida (vence_en pasado o estado VENCIDA/CANCELADA): el personal que no es
      ADMIN no usa la plataforma (402): el unico que puede entrar a renovar es el ADMIN. Los
      endpoints de gestion del ADMIN igual responden 402 via requiere_funcion_plan.
    La plataforma (empresa_id NULL) no depende de ninguna empresa.

    Es la version "suelta" (hace su propia consulta) para el login y las rutas que no pasan por
    get_staff_actual; el resto de los endpoints de personal ya traen estos datos en la consulta
    unica de _SQL_PERSONAL."""
    if empresa_id is None:
        return
    fila = await conn.fetchrow(
        f"""
        SELECT em.activa, r.nombre AS rol, {_VIGENTE} AS vigente
          FROM empresa em
          LEFT JOIN suscripcion su ON su.empresa_id = em.id
          LEFT JOIN usuario u ON u.id = $2
          LEFT JOIN rol r ON r.id = u.rol_id
         WHERE em.id = $1
        """,
        empresa_id,
        usuario_id,
    )
    if fila is None:
        _evaluar_empresa(False, False, None, ruta)
    else:
        _evaluar_empresa(fila["activa"], fila["vigente"], fila["rol"], ruta)


async def _empleado_con_permiso(
    conn: asyncpg.Connection, usuario: dict, codigo: str, detalle: str, ruta: str | None = None
) -> dict:
    if usuario["tipo"] != "STAFF":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=detalle)

    # una sola consulta con permisos, estado de la empresa y fila de empleado; los chequeos se
    # hacen en el mismo orden de siempre (permiso, empresa, sucursal) para no cambiar el error
    fila = await conn.fetchrow(_SQL_EMPLEADO_OPERATIVO, usuario["id"])
    if fila is None or codigo not in fila["permisos"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu rol no tiene permiso para esta operacion",
        )
    if fila["empresa_id"] is not None:
        _evaluar_empresa(fila["activa"], fila["vigente"], fila["rol"], ruta)

    if not fila["sucursal_propia"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu usuario no esta asignado a una sucursal",
        )

    return {
        "usuario_id": usuario["id"],
        "sucursal_id": fila["sucursal_id"],
        "empresa_id": fila["empresa_id"],
    }


async def get_cajero_actual(
    request: Request,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> dict:
    """CU07: STAFF con permiso `caja.crear` y sucursal asignada."""
    return await _empleado_con_permiso(
        conn, usuario, "caja.crear", "Solo el personal de caja puede operar la caja", request.url.path
    )


async def get_encargado_actual(
    request: Request,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> dict:
    """CU08: STAFF con permiso `reservas.actualizar` y sucursal asignada."""
    return await _empleado_con_permiso(
        conn,
        usuario,
        "reservas.actualizar",
        "Solo el encargado de sucursal puede atender reservas",
        request.url.path,
    )


async def obtener_permisos(conn: asyncpg.Connection, usuario_id) -> list[str]:
    """Codigos de permiso que el rol del usuario tiene concedidos (tablas rol, rol_permiso,
    permiso). Un CLIENTE nunca tiene rol, asi que siempre devuelve lista vacia."""
    filas = await conn.fetch(
        """
        SELECT p.codigo
        FROM usuario u
        JOIN rol_permiso rp ON rp.rol_id = u.rol_id
        JOIN permiso p      ON p.id = rp.permiso_id
        WHERE u.id = $1
        ORDER BY p.codigo
        """,
        usuario_id,
    )
    return [fila["codigo"] for fila in filas]


async def get_staff_actual(
    request: Request,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> dict:
    """Usuario STAFF con su rol, su empresa (None = plataforma), sus permisos y (si esta atado
    a una) su sucursal. Todo sale de una sola consulta (_SQL_PERSONAL); el plan de la empresa
    queda en request.state.plan_empresa para que requiere_funcion_plan no lo vuelva a pedir."""
    if usuario["tipo"] != "STAFF":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Esta seccion es solo para el personal",
        )

    fila = await conn.fetchrow(_SQL_PERSONAL, usuario["id"])
    if fila is None or fila["rol"] is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu usuario no tiene un rol asignado",
        )
    if fila["empresa_id"] is not None:
        _evaluar_empresa(fila["activa"], fila["vigente"], fila["rol"], request.url.path)
        request.state.plan_empresa = fila if fila["suscripcion_id"] is not None else None

    return {
        "id": fila["id"],
        "rol": fila["rol"],
        "empresa_id": fila["empresa_id"],
        "sucursal_id": fila["sucursal_id"],
        "cargo": fila["cargo"],
        "permisos": list(fila["permisos"]),
    }


def requiere_permiso(*codigos: str):
    """Dependencia de autorizacion por permiso (CU13). Basta con tener uno de los codigos
    pedidos."""

    async def verificar(staff: dict = Depends(get_staff_actual)) -> dict:
        if not any(codigo in staff["permisos"] for codigo in codigos):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Tu rol no tiene permiso para esta operacion",
            )
        return staff

    return verificar

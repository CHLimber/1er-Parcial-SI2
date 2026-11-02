"""Que tablas entran en cada tipo de copia de seguridad.

  - Copia GENERAL (plataforma): todas las tablas de `public`, descubiertas en el catalogo de
    Postgres, salvo EXCLUIDAS_GENERAL. Asi una tabla nueva queda respaldada sin tocar este archivo.
  - Copia de una EMPRESA: cada tabla con el filtro que la ata a la empresa. Es una lista a mano
    porque el filtro depende del camino de claves foraneas de cada tabla (venta -> sucursal ->
    empresa, venta_detalle -> venta, ...). tests/test_backups.py compara esta lista con
    db/01_schema.sql: una tabla nueva sin clasificar rompe el test, en vez de quedar fuera de
    la copia sin que nadie se entere.

`$1` en los filtros es siempre el id de la empresa. Los filtros solo usan constantes de este
archivo (nunca texto de un request), por eso se interpolan en el SQL.
"""

from dataclasses import dataclass

# Tablas que no se respaldan en ninguna copia.
#   backup:       es el registro de las propias copias (circular y sin valor).
#   sesion_token: sesiones efimeras; restaurar una sesion vieja seria un hueco de seguridad.
#   dispositivo_push: tokens de Firebase de celulares; restaurar uno viejo manda avisos a un telefono
#                     que ya no es de esa persona. La app los vuelve a registrar al abrir sesion.
EXCLUIDAS_GENERAL = frozenset({"backup", "sesion_token", "dispositivo_push"})

# Columnas que NO viajan en la copia de una empresa: ese archivo lo descarga su administrador y
# el hash de contrasena de una clienta (que es de la plataforma, no de la empresa) o de otra
# persona del personal no es suyo para llevarselo. La copia general, que solo ve la plataforma y
# existe para recuperar el sistema completo, si las lleva.
COLUMNAS_SENSIBLES = {"usuario": ["password_hash"]}

_SUCURSALES = "(SELECT id FROM sucursal WHERE empresa_id = $1)"
_VARIANTES = (
    "(SELECT pv.id FROM producto_variante pv JOIN producto p ON p.id = pv.producto_id "
    "WHERE p.empresa_id = $1)"
)
_CAJAS = f"(SELECT id FROM caja WHERE sucursal_id IN {_SUCURSALES})"
_ROLES = "(SELECT id FROM rol WHERE empresa_id = $1)"
_VENTAS = f"(SELECT id FROM venta WHERE sucursal_id IN {_SUCURSALES})"
_PAGOS = f"(SELECT id FROM pago WHERE venta_id IN {_VENTAS})"
_ENVIOS = f"(SELECT id FROM envio WHERE sucursal_id IN {_SUCURSALES})"
_RESERVAS = f"(SELECT id FROM reserva WHERE sucursal_id IN {_SUCURSALES})"
_RECEPCIONES = f"(SELECT id FROM recepcion WHERE sucursal_id IN {_SUCURSALES})"
_DEVOLUCIONES = f"(SELECT id FROM devolucion WHERE sucursal_id IN {_SUCURSALES})"
_PERSONAL = "(SELECT id FROM usuario WHERE empresa_id = $1)"
_TRASPASOS = (
    f"(SELECT id FROM traspaso WHERE sucursal_origen_id IN {_SUCURSALES} "
    f"OR sucursal_destino_id IN {_SUCURSALES})"
)
# Las clientas son de la plataforma (usuario.empresa_id NULL): pertenecen a la empresa por
# haber comprado o reservado en ella o por estar en su cartera.
_CLIENTAS = f"""(
    SELECT usuario_id FROM cliente_perfil_tenant WHERE empresa_id = $1
    UNION SELECT usuario_id FROM venta WHERE sucursal_id IN {_SUCURSALES} AND usuario_id IS NOT NULL
    UNION SELECT usuario_id FROM reserva WHERE sucursal_id IN {_SUCURSALES}
)"""
_CARRITOS = f"""(
    SELECT carrito_id FROM carrito_item WHERE variante_id IN {_VARIANTES}
    UNION SELECT carrito_id FROM venta WHERE sucursal_id IN {_SUCURSALES} AND carrito_id IS NOT NULL
)"""


@dataclass(frozen=True)
class TablaEmpresa:
    nombre: str
    donde: str  # filtro SQL sobre la tabla (sin la palabra WHERE); $1 = empresa_id


# Catalogos compartidos por todas las empresas: viajan completos porque las filas de la empresa
# los referencian (talla_id, color_id, permiso_id, plan_id) y sin ellos la copia no se entiende.
_COMPARTIDAS = ("talla", "color", "permiso", "plan")

# Las tablas por empresa, en orden de dependencia (la restauracion de manana puede insertar en
# este mismo orden).
TABLAS_EMPRESA: tuple[TablaEmpresa, ...] = (
    *(TablaEmpresa(nombre, "TRUE") for nombre in _COMPARTIDAS),
    TablaEmpresa("empresa", "id = $1"),
    TablaEmpresa("suscripcion", "empresa_id = $1"),
    TablaEmpresa("pago_suscripcion", "suscripcion_id IN (SELECT id FROM suscripcion WHERE empresa_id = $1)"),
    TablaEmpresa("rol", "empresa_id = $1"),
    TablaEmpresa("rol_permiso", f"rol_id IN {_ROLES}"),
    TablaEmpresa("usuario", f"empresa_id = $1 OR id IN {_CLIENTAS}"),
    TablaEmpresa("perfil_cliente", f"usuario_id IN {_CLIENTAS}"),
    TablaEmpresa("direccion", f"usuario_id IN {_CLIENTAS}"),
    TablaEmpresa("cliente_perfil_tenant", "empresa_id = $1"),
    TablaEmpresa("sucursal", "empresa_id = $1"),
    TablaEmpresa("empleado", f"sucursal_id IN {_SUCURSALES}"),
    TablaEmpresa("caja", f"sucursal_id IN {_SUCURSALES}"),
    TablaEmpresa("sesion_caja", f"caja_id IN {_CAJAS}"),
    TablaEmpresa("proveedor", "empresa_id = $1"),
    TablaEmpresa("categoria", "empresa_id = $1"),
    TablaEmpresa("marca", "empresa_id = $1"),
    TablaEmpresa("temporada", "empresa_id = $1"),
    TablaEmpresa("coleccion", "empresa_id = $1"),
    TablaEmpresa("promocion", "empresa_id = $1"),
    TablaEmpresa("producto", "empresa_id = $1"),
    TablaEmpresa("producto_variante", "producto_id IN (SELECT id FROM producto WHERE empresa_id = $1)"),
    TablaEmpresa("producto_imagen", "producto_id IN (SELECT id FROM producto WHERE empresa_id = $1)"),
    TablaEmpresa("inventario", f"sucursal_id IN {_SUCURSALES}"),
    TablaEmpresa("movimiento_inventario", f"sucursal_id IN {_SUCURSALES}"),
    TablaEmpresa("recepcion", f"sucursal_id IN {_SUCURSALES}"),
    TablaEmpresa("recepcion_detalle", f"recepcion_id IN {_RECEPCIONES}"),
    TablaEmpresa("traspaso", f"id IN {_TRASPASOS}"),
    TablaEmpresa("traspaso_detalle", f"traspaso_id IN {_TRASPASOS}"),
    TablaEmpresa("reserva", f"sucursal_id IN {_SUCURSALES}"),
    TablaEmpresa("reserva_detalle", f"reserva_id IN {_RESERVAS}"),
    TablaEmpresa("reserva_historial", f"reserva_id IN {_RESERVAS}"),
    TablaEmpresa("carrito", f"id IN {_CARRITOS}"),
    TablaEmpresa("carrito_item", f"variante_id IN {_VARIANTES}"),
    TablaEmpresa("venta", f"sucursal_id IN {_SUCURSALES}"),
    TablaEmpresa("venta_detalle", f"venta_id IN {_VENTAS}"),
    TablaEmpresa("pago", f"venta_id IN {_VENTAS}"),
    TablaEmpresa("evento_pasarela", f"pago_id IN {_PAGOS}"),
    TablaEmpresa("comprobante", f"venta_id IN {_VENTAS}"),
    TablaEmpresa("envio", f"sucursal_id IN {_SUCURSALES}"),
    TablaEmpresa("envio_evento", f"envio_id IN {_ENVIOS}"),
    TablaEmpresa("devolucion", f"sucursal_id IN {_SUCURSALES}"),
    TablaEmpresa("devolucion_detalle", f"devolucion_id IN {_DEVOLUCIONES}"),
    TablaEmpresa("notificacion", f"usuario_id IN {_PERSONAL}"),
    TablaEmpresa("auditoria", "empresa_id = $1"),
    TablaEmpresa("operacion_sync", "empresa_id = $1"),
)

# Tablas del esquema que la copia de una empresa NO lleva, con el motivo.
EXCLUIDAS_EMPRESA = {
    "backup": "es el registro de las copias",
    "sesion_token": "sesiones efimeras",
    "dispositivo_push": "tokens de celulares; la app los registra de nuevo al iniciar sesion",
    "configuracion": "parametros de toda la plataforma, no de una empresa",
}

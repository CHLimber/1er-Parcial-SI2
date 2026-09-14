-- =====================================================================
--  Reparacion: matriz de permisos de CU13 (tablas permiso / rol_permiso)
--
--  Para una base donde 03_datos_iniciales.sql quedo aplicado a medias y los roles
--  existen pero sin permisos: el login funciona y `UsuarioOut.permisos` vuelve vacio,
--  asi que requiere_permiso() rechaza todo CU09-CU13 con 403 aunque el usuario sea ADMIN.
--
--  Es idempotente (ON CONFLICT DO NOTHING sobre permiso.codigo y la PK de rol_permiso):
--  se puede correr las veces que haga falta y no toca usuarios, catalogo ni inventario.
--  No reemplaza a 03_datos_iniciales.sql, solo repone este bloque.
--
--  Este archivo vive en db/reparaciones/ a proposito: docker-entrypoint-initdb.d solo
--  ejecuta lo que esta en el primer nivel de db/, asi que no se corre solo en local.
--
--  Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/permisos_cu13.sql
-- =====================================================================

BEGIN;

-- 1. Los 19 codigos de permiso que conoce el backend (app/core/deps.py y los routers).
INSERT INTO permiso (codigo, modulo, descripcion) VALUES
    ('usuarios.ver',           'usuarios',    'Consultar el padron de usuarios'),
    ('usuarios.gestionar',     'usuarios',    'Crear, editar y dar de baja usuarios'),
    ('roles.ver',              'usuarios',    'Consultar roles y sus permisos'),
    ('roles.gestionar',        'usuarios',    'Crear roles y reasignar sus permisos'),
    ('catalogo.ver',           'catalogo',    'Consultar el catalogo completo, incluido lo inactivo'),
    ('catalogo.gestionar',     'catalogo',    'Alta, baja y modificacion de prendas y variantes'),
    ('proveedores.ver',        'compras',     'Consultar proveedores'),
    ('proveedores.gestionar',  'compras',     'Alta, baja y modificacion de proveedores'),
    ('sucursales.ver',         'organizacion','Consultar sucursales y cajas'),
    ('sucursales.gestionar',   'organizacion','Alta, baja y modificacion de sucursales y cajas'),
    ('inventario.ver',         'inventario',  'Consultar existencias y kardex'),
    ('inventario.ajustar',     'inventario',  'Registrar ajustes manuales de stock'),
    ('recepciones.ver',        'inventario',  'Consultar recepciones de mercaderia'),
    ('recepciones.registrar',  'inventario',  'Cargar recepciones en borrador'),
    ('recepciones.confirmar',  'inventario',  'Confirmar o anular una recepcion'),
    ('reservas.atender',       'reservas',    'Atender la cola de reservas de la sucursal'),
    ('caja.operar',            'ventas',      'Abrir y cerrar sesiones de caja'),
    ('ventas.pos',             'ventas',      'Registrar ventas presenciales'),
    ('reportes.ver',           'reportes',    'Consultar los tableros de gestion')
ON CONFLICT (codigo) DO NOTHING;

-- 2. Los cinco roles de sistema, por si tampoco estuvieran.
INSERT INTO rol (nombre, descripcion, es_sistema) VALUES
    ('ADMIN',     'Administracion general del sistema', TRUE),
    ('ENCARGADO', 'Responsable de una sucursal', TRUE),
    ('CAJERO',    'Maneja caja y ventas presenciales', TRUE),
    ('VENDEDOR',  'Atiende clientes y reservas en tienda', TRUE),
    ('ALMACEN',   'Recibe mercaderia y controla existencias', TRUE)
ON CONFLICT (nombre) DO NOTHING;

-- 3. Asignacion rol -> permisos, identica a 03_datos_iniciales.sql.

-- ADMIN: todo
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'ADMIN'), p.id FROM permiso p
ON CONFLICT DO NOTHING;

-- ENCARGADO: manda en su sucursal (inventario, recepciones, reservas, reportes)
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'ENCARGADO'), p.id
  FROM permiso p
 WHERE p.codigo IN ('usuarios.ver','catalogo.ver','proveedores.ver','sucursales.ver',
                    'inventario.ver','inventario.ajustar','recepciones.ver',
                    'recepciones.registrar','recepciones.confirmar','reservas.atender',
                    'reportes.ver')
ON CONFLICT DO NOTHING;

-- ALMACEN: solo el flujo de entrada de mercaderia
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'ALMACEN'), p.id
  FROM permiso p
 WHERE p.codigo IN ('catalogo.ver','proveedores.ver','inventario.ver','inventario.ajustar',
                    'recepciones.ver','recepciones.registrar','recepciones.confirmar')
ON CONFLICT DO NOTHING;

-- CAJERO: caja y punto de venta
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'CAJERO'), p.id
  FROM permiso p
 WHERE p.codigo IN ('catalogo.ver','inventario.ver','caja.operar','ventas.pos')
ON CONFLICT DO NOTHING;

-- VENDEDOR: piso de venta y vestidores
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'VENDEDOR'), p.id
  FROM permiso p
 WHERE p.codigo IN ('catalogo.ver','inventario.ver','reservas.atender')
ON CONFLICT DO NOTHING;

COMMIT;

-- Resultado esperado: ADMIN 19, ENCARGADO 11, ALMACEN 7, CAJERO 4, VENDEDOR 3.
SELECT r.nombre AS rol, COUNT(rp.permiso_id) AS permisos
  FROM rol r
  LEFT JOIN rol_permiso rp ON rp.rol_id = r.id
 GROUP BY r.nombre
 ORDER BY permisos DESC;

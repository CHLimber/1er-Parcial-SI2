-- =====================================================================
--  Reparacion/migracion: matriz de permisos de CU13 (tablas permiso / rol_permiso)
--
--  Sirve para dos casos, sobre una base ya desplegada (tipico: Railway) que no se
--  puede recrear con "docker compose down -v":
--
--  1. 03_datos_iniciales.sql quedo aplicado a medias y los roles existen pero sin
--     permisos: el login funciona y `UsuarioOut.permisos` vuelve vacio, asi que
--     requiere_permiso() rechaza todo CU09-CU13 con 403 aunque el usuario sea ADMIN.
--  2. La base todavia tiene los 19 codigos "viejos" (<modulo>.ver / .gestionar / ...)
--     de antes de que CU13 pasara a CRUD estricto (<modulo>.leer/crear/actualizar/
--     eliminar). Este script renombra esos codigos in-place (UPDATE, no INSERT+DELETE)
--     para no perder el id de permiso.id que ya esta referenciado en rol_permiso, y
--     agrega los codigos nuevos que separan una accion vieja en varias CRUD.
--
--  Es idempotente: se puede correr las veces que haga falta. No toca usuarios,
--  catalogo ni inventario. No reemplaza a 03_datos_iniciales.sql, solo repone/migra
--  este bloque.
--
--  Este archivo vive en db/reparaciones/ a proposito: docker-entrypoint-initdb.d solo
--  ejecuta lo que esta en el primer nivel de db/, asi que no se corre solo en local.
--
--  Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/permisos_cu13.sql
-- =====================================================================

BEGIN;

-- 0. Los cinco roles de sistema, por si tampoco estuvieran.
INSERT INTO rol (nombre, descripcion, es_sistema) VALUES
    ('ADMIN',     'Administracion general del sistema', TRUE),
    ('ENCARGADO', 'Responsable de una sucursal', TRUE),
    ('CAJERO',    'Maneja caja y ventas presenciales', TRUE),
    ('VENDEDOR',  'Atiende clientes y reservas en tienda', TRUE),
    ('ALMACEN',   'Recibe mercaderia y controla existencias', TRUE)
ON CONFLICT (nombre) DO NOTHING;

-- 1. Migrar los codigos viejos a los nuevos, conservando permiso.id (UPDATE, no
--    INSERT+DELETE) para que rol_permiso no pierda sus vinculos. Una base nueva
--    (creada ya con 03_datos_iniciales.sql en su version CRUD) no tiene estas filas
--    "viejas", asi que estos UPDATE no afectan nada.
UPDATE permiso SET codigo = 'usuarios.leer',        modulo = 'usuarios'    WHERE codigo = 'usuarios.ver';
UPDATE permiso SET codigo = 'usuarios.actualizar',  modulo = 'usuarios'    WHERE codigo = 'usuarios.gestionar';
UPDATE permiso SET codigo = 'roles.leer',           modulo = 'roles'      WHERE codigo = 'roles.ver';
UPDATE permiso SET codigo = 'roles.actualizar',     modulo = 'roles'      WHERE codigo = 'roles.gestionar';
UPDATE permiso SET codigo = 'catalogo.leer',        modulo = 'catalogo'    WHERE codigo = 'catalogo.ver';
UPDATE permiso SET codigo = 'catalogo.actualizar',  modulo = 'catalogo'    WHERE codigo = 'catalogo.gestionar';
UPDATE permiso SET codigo = 'proveedores.leer',       modulo = 'proveedores' WHERE codigo = 'proveedores.ver';
UPDATE permiso SET codigo = 'proveedores.actualizar', modulo = 'proveedores' WHERE codigo = 'proveedores.gestionar';
UPDATE permiso SET codigo = 'sucursales.leer',        modulo = 'sucursales'  WHERE codigo = 'sucursales.ver';
UPDATE permiso SET codigo = 'sucursales.actualizar',  modulo = 'sucursales'  WHERE codigo = 'sucursales.gestionar';
UPDATE permiso SET codigo = 'inventario.leer',        modulo = 'inventario'  WHERE codigo = 'inventario.ver';
UPDATE permiso SET codigo = 'inventario.actualizar',  modulo = 'inventario'  WHERE codigo = 'inventario.ajustar';
UPDATE permiso SET codigo = 'recepciones.leer',       modulo = 'recepciones' WHERE codigo = 'recepciones.ver';
UPDATE permiso SET codigo = 'recepciones.crear',      modulo = 'recepciones' WHERE codigo = 'recepciones.registrar';
UPDATE permiso SET codigo = 'recepciones.actualizar', modulo = 'recepciones' WHERE codigo = 'recepciones.confirmar';
UPDATE permiso SET codigo = 'reservas.actualizar',    modulo = 'reservas'    WHERE codigo = 'reservas.atender';
UPDATE permiso SET codigo = 'caja.crear',             modulo = 'caja'        WHERE codigo = 'caja.operar';
UPDATE permiso SET codigo = 'ventas.crear',           modulo = 'ventas'      WHERE codigo = 'ventas.pos';
UPDATE permiso SET codigo = 'reportes.leer',          modulo = 'reportes'    WHERE codigo = 'reportes.ver';

-- 2. Codigos nuevos que no tienen equivalente viejo (una accion CRUD que antes no
--    existia como permiso independiente). Los 19 UPDATE de arriba son no-op en una
--    base que ya esta en CRUD estricto, asi que este INSERT cubre ambos casos.
INSERT INTO permiso (codigo, modulo, descripcion) VALUES
    ('usuarios.crear',        'usuarios',    'Dar de alta personal'),
    ('usuarios.eliminar',     'usuarios',    'Dar de baja usuarios'),
    ('roles.crear',           'roles',       'Crear roles'),
    ('roles.eliminar',        'roles',       'Eliminar roles que no son del sistema'),
    ('catalogo.crear',        'catalogo',    'Alta de prendas, variantes, imagenes, categorias y marcas'),
    ('catalogo.eliminar',     'catalogo',    'Baja de prendas, variantes, categorias e imagenes'),
    ('proveedores.crear',     'proveedores', 'Dar de alta proveedores'),
    ('proveedores.eliminar',  'proveedores', 'Dar de baja proveedores'),
    ('sucursales.crear',      'sucursales',  'Dar de alta sucursales y cajas'),
    ('sucursales.eliminar',   'sucursales',  'Dar de baja sucursales y cajas'),
    ('recepciones.eliminar',  'recepciones', 'Quitar lineas del borrador y anular una recepcion'),
    ('reservas.leer',         'reservas',    'Consultar la cola de reservas de la sucursal'),
    ('caja.leer',             'caja',        'Consultar el estado de las cajas'),
    ('caja.actualizar',       'caja',        'Cerrar una sesion de caja'),
    ('ventas.leer',           'ventas',      'Consultar ventas'),
    ('auditoria.leer',        'auditoria',   'Consultar la bitacora de auditoria del sistema')
ON CONFLICT (codigo) DO NOTHING;

-- 3. Asignacion rol -> permisos, identica a 03_datos_iniciales.sql. Se reemplaza por
--    completo la de los roles no-ADMIN porque el set de acciones cambio (una accion
--    vieja ahora puede cubrir 2 o 3 codigos nuevos).

-- ADMIN: todo (incluye los codigos nuevos del paso 2)
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'ADMIN'), p.id FROM permiso p
ON CONFLICT DO NOTHING;

DELETE FROM rol_permiso WHERE rol_id = (SELECT id FROM rol WHERE nombre = 'ENCARGADO');
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'ENCARGADO'), p.id
  FROM permiso p
 WHERE p.codigo IN ('usuarios.leer','catalogo.leer','proveedores.leer','sucursales.leer',
                    'inventario.leer','inventario.actualizar',
                    'recepciones.leer','recepciones.crear','recepciones.actualizar','recepciones.eliminar',
                    'reservas.leer','reservas.actualizar',
                    'reportes.leer');

DELETE FROM rol_permiso WHERE rol_id = (SELECT id FROM rol WHERE nombre = 'ALMACEN');
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'ALMACEN'), p.id
  FROM permiso p
 WHERE p.codigo IN ('catalogo.leer','proveedores.leer','inventario.leer','inventario.actualizar',
                    'recepciones.leer','recepciones.crear','recepciones.actualizar','recepciones.eliminar');

DELETE FROM rol_permiso WHERE rol_id = (SELECT id FROM rol WHERE nombre = 'CAJERO');
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'CAJERO'), p.id
  FROM permiso p
 WHERE p.codigo IN ('catalogo.leer','inventario.leer','caja.leer','caja.crear','caja.actualizar','ventas.crear');

DELETE FROM rol_permiso WHERE rol_id = (SELECT id FROM rol WHERE nombre = 'VENDEDOR');
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'VENDEDOR'), p.id
  FROM permiso p
 WHERE p.codigo IN ('catalogo.leer','inventario.leer','reservas.leer','reservas.actualizar');

COMMIT;

-- Resultado esperado: ADMIN 35, ENCARGADO 13, ALMACEN 8, CAJERO 6, VENDEDOR 4.
-- (auditoria.leer, CU19, queda solo para ADMIN -- ver comentario en 03_datos_iniciales.sql)
SELECT r.nombre AS rol, COUNT(rp.permiso_id) AS permisos
  FROM rol r
  LEFT JOIN rol_permiso rp ON rp.rol_id = r.id
 GROUP BY r.nombre
 ORDER BY permisos DESC;

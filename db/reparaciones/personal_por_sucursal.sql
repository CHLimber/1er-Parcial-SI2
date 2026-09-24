-- =====================================================================
--  Reparacion/migracion: personal por sucursal y CU07/CU08 por permiso (PENDIENTES 3.1)
--
--  Los cinco cargos se mantienen (ENCARGADO, CAJERO, VENDEDOR, ALMACEN; ADMIN es rol): la
--  reduccion de actores de 2.19.1.d se descarto. Este script solo deja la base desplegada
--  (Railway) igual que el seed actual:
--    1. Da al ENCARGADO caja.leer/caja.crear/caja.actualizar/ventas.crear (CU07 se autoriza
--       por el permiso caja.crear y CU08 por reservas.actualizar, ver
--       get_cajero_actual/get_encargado_actual en backend/app/core/deps.py), para que pueda
--       cubrir la caja si el cajero falta.
--    2. Actualiza las descripciones de caja.crear, reservas.actualizar y el rol CAJERO
--       (cosmetico).
--    3. Cuentas demo: cada sucursal con al menos un ENCARGADO y un CAJERO. Crea cajera.scz
--       (Equipetrol), encargado.cbba (Cala Cala) y cajera.lapaz (Sopocachi) si faltan, y
--       renombra a las personas de vendedor.scz/almacen.scz como en el seed. Solo si la base
--       trae el seed demo: en una base sin esas sucursales no hace nada.
--
--  Es re-ejecutable: todo se guarda por existencia. No toca el ENUM cargo_empleado.
--  Despues de correrlo: volver a iniciar sesion en web/movil para que UsuarioOut traiga los
--  permisos nuevos.
--
--  Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/personal_por_sucursal.sql
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. El ENCARGADO puede cubrir la caja. El ADMIN ya tiene todos los permisos, pero se
--    re-asegura por si su matriz se edito desde CU13.
-- ---------------------------------------------------------------------

INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
  FROM rol r
  JOIN permiso p ON p.codigo IN ('caja.leer','caja.crear','caja.actualizar','ventas.crear',
                                 'reservas.leer','reservas.actualizar')
 WHERE r.nombre IN ('ENCARGADO','ADMIN')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. Descripciones (cosmetico)
-- ---------------------------------------------------------------------

UPDATE rol SET descripcion = 'Maneja caja, ventas presenciales y verificacion de pagos'
 WHERE nombre = 'CAJERO';
UPDATE permiso
   SET descripcion = 'Operar la caja de su sucursal: abrir sesion, vender, verificar pagos QR/efectivo (CU07)'
 WHERE codigo = 'caja.crear';
UPDATE permiso
   SET descripcion = 'Atender reservas de su sucursal: confirmar, rechazar, preparar, resolver (CU08)'
 WHERE codigo = 'reservas.actualizar';

-- ---------------------------------------------------------------------
-- 3. Cuentas demo del seed (ver db/03_datos_iniciales.sql)
-- ---------------------------------------------------------------------

UPDATE usuario SET nombre = 'Daniela', apellido = 'Vargas'
 WHERE email = 'vendedor.scz@fashionstore.bo';
UPDATE usuario SET nombre = 'Marco', apellido = 'Gutierrez'
 WHERE email = 'almacen.scz@fashionstore.bo';

INSERT INTO usuario (email, password_hash, nombre, apellido, tipo, rol_id, email_verificado)
SELECT v.email, crypt('demo1234', gen_salt('bf')), v.nombre, v.apellido, 'STAFF',
       (SELECT id FROM rol WHERE nombre = v.rol), TRUE
  FROM (VALUES ('cajera.scz@fashionstore.bo',     'Camila', 'Rocha',   'CAJERO',    'SC-01'),
               ('encargado.cbba@fashionstore.bo', 'Ruben',  'Mamani',  'ENCARGADO', 'CB-01'),
               ('cajera.lapaz@fashionstore.bo',   'Lucia',  'Condori', 'CAJERO',    'LP-01'))
       AS v(email, nombre, apellido, rol, sucursal)
 WHERE EXISTS (SELECT 1 FROM sucursal WHERE codigo = v.sucursal)
   AND NOT EXISTS (SELECT 1 FROM usuario WHERE email = v.email);

INSERT INTO empleado (usuario_id, sucursal_id, cargo, fecha_ingreso)
SELECT u.id, (SELECT id FROM sucursal WHERE codigo = v.sucursal), v.cargo::cargo_empleado,
       CURRENT_DATE
  FROM (VALUES ('cajera.scz@fashionstore.bo',     'CAJERO',    'SC-01'),
               ('encargado.cbba@fashionstore.bo', 'ENCARGADO', 'CB-01'),
               ('cajera.lapaz@fashionstore.bo',   'CAJERO',    'LP-01'))
       AS v(email, cargo, sucursal)
  JOIN usuario u ON u.email = v.email
 WHERE NOT EXISTS (SELECT 1 FROM empleado e WHERE e.usuario_id = u.id);

COMMIT;

-- Resultado esperado (base demo): cada sucursal activa con al menos 1 encargado y 1 cajero, y
-- el conteo de permisos por rol.
SELECT s.codigo,
       count(*) FILTER (WHERE e.cargo = 'ENCARGADO') AS encargados,
       count(*) FILTER (WHERE e.cargo = 'CAJERO')    AS cajeros,
       count(*) FILTER (WHERE e.cargo = 'VENDEDOR')  AS vendedores,
       count(*) FILTER (WHERE e.cargo = 'ALMACEN')   AS almacen
  FROM sucursal s
  LEFT JOIN empleado e ON e.sucursal_id = s.id AND e.activo
 WHERE s.activa
 GROUP BY s.codigo
 ORDER BY s.codigo;

SELECT r.nombre, count(rp.permiso_id) AS permisos
  FROM rol r LEFT JOIN rol_permiso rp ON rp.rol_id = r.id
 GROUP BY r.nombre ORDER BY r.nombre;

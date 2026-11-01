-- Planes mas distintos entre si (la portada y /planes los comparan lado a lado).
--   BASICO:      2 sucursales, 5 personas, 2 cajas; sin perfiles de clientas ni traspasos.
--   PROFESIONAL: 10 sucursales, personal y cajas sin limite, con todas las funciones.
-- Idempotente. Las empresas que ya estan en BASICO con mas personal o cajas que el nuevo tope
-- siguen operando: los topes solo frenan altas nuevas (exigir_limite), no dan de baja nada.
UPDATE plan
   SET max_sucursales = 2, max_empleados = 5, max_cajas = 2,
       perfiles_clientes = FALSE, traspasos = FALSE, operacion_offline = TRUE, reportes = TRUE,
       ia_reportes = FALSE, analitica_ml = FALSE,
       descripcion = 'Para tiendas que arrancan: hasta 2 sucursales con caja, reservas, ventas online, venta sin conexion y reportes convencionales'
 WHERE codigo = 'BASICO';

UPDATE plan
   SET max_sucursales = 10, max_empleados = NULL, max_cajas = NULL,
       perfiles_clientes = TRUE, traspasos = TRUE, operacion_offline = TRUE, reportes = TRUE,
       ia_reportes = TRUE, analitica_ml = TRUE,
       descripcion = 'Para cadenas que crecen: hasta 10 sucursales, personal y cajas sin limite, perfiles de clientas, traspasos, reportes con IA y analitica predictiva'
 WHERE codigo = 'PROFESIONAL';

# SaaS multitenant — Análisis y diseño con ICONIX (UML 2.5.1)

Este documento cubre la especificación técnica «FashionStore SaaS Multitenant» (18/10/2026). La
especificación cambia una decisión del documento anterior (`ICONIX_SEGUNDO_PARCIAL.md`): **el
tenant es la empresa contratante, no la sucursal**. Lo demás de ese documento sigue valiendo:
cambio por talla, traspasos por demanda, pérdidas, reportes con IA y PWA.

Las narrativas usan el **catálogo vigente CU01-CU29** de `../PARCIALES.md`. Se escribieron con la
numeración de la especificación (CU01 a CU28); la equivalencia está en la sección 6.5 de ese
archivo. El diagrama `24` todavía muestra la numeración de la especificación. Los diagramas se
escribieron leyendo el código del 18/10/2026.

| Etapa ICONIX | Artefacto | Archivo |
|---|---|---|
| Análisis de requisitos | Modelo de dominio multitenant | `23_modelo_dominio_multitenant.puml` |
| Análisis de requisitos | Casos de uso y narrativas | `24_casos_de_uso_multitenant.puml` y sección 2 |
| Análisis preliminar | Robustez (= comunicación) | `25_robustez_sincronizacion.puml`, `28_robustez_analitica_ml.puml` |
| Diseño | Secuencia de CU22 | `26_secuencia_sincronizar.puml` |
| Diseño | Base local SQLite del móvil | `27_modelo_datos_sqlite_movil.puml` |

Para regenerar los PNG (Java 8 o superior y `plantuml.jar`):

```bash
cd fashionstore/docs/uml
java -jar plantuml.jar -charset UTF-8 -tpng -o png 2*.puml
```

Si una figura sale como «An error has occured: IllegalStateException», el layout `smetana` no
soporta una nota adjunta a una clase. Hay que pasar la nota a una `legend`, como se hizo en el 23.

## 1. Modelo de dominio y aislamiento entre empresas

- **Plataforma:** administra las empresas, los planes y las suscripciones. Es el rol
  `SUPERADMIN` y no pertenece a ninguna empresa.
- **Empresa (tenant):** tiene una `Suscripcion` a un `Plan` y es dueña de todo lo demás:
  - sucursales, usuarios, roles propios y cartera de clientas;
  - catálogo (producto, categoría, talla, color, temporada), proveedores y promociones;
  - por medio de sus sucursales: inventario, ventas, reservas y pagos.
- **Clienta:** su cuenta es de la plataforma. Elige la tienda que mira.

**Cómo se impide el acceso cruzado (5.5 de la especificación):**

1. **En el backend.** `app/core/tenant.py` toma la empresa del token del personal, nunca de un
   parámetro, y todo SQL filtra por ella. Un recurso de otra empresa responde **404**: así ni
   siquiera se confirma que existe. La pertenencia se valida con `exigir_sucursal`,
   `exigir_variantes` y `exigir_fila`.
2. **En la base.** `fn_mover_inventario` rechaza mover stock de una prenda de otra empresa, aunque
   el backend tuviera un error.
3. **Para la clienta.** El header `X-Empresa` elige qué tienda ve, y el carrito no mezcla
   prendas de dos empresas.

Lo prueba `scripts/e2e_multitenant.py` con 122 chequeos. Entre ellos están los accesos cruzados
de una empresa a otra, que tienen que dar 404.

**Planes (configurables con `PUT /saas/planes/{codigo}`):**

| | Básico | Profesional |
|---|---|---|
| Sucursales activas | hasta 2 | hasta 10 |
| Operación offline y reportes convencionales | sí | sí |
| Reportes con IA y analítica ML | no (403) | sí |

**Política de suscripción vencida (RN06, punto ambiguo 19):**

- Las funciones del plan responden **402**.
- El personal puede entrar, ver el plan y renovarlo.
- La tienda pública sigue funcionando para no castigar a la clienta.
- De las operaciones offline, se acepta lo registrado **antes** del vencimiento y se rechaza lo
  registrado después (`SUSCRIPCION_VENCIDA`).

## 2. Narrativas

### CU01 Gestionar empresas (registrar)

- **Actor:** Administrador de plataforma.
- **Curso básico:**
  1. El Administrador abre «Empresas» y completa slug, nombre, razón social, NIT, el plan inicial
     y los datos del administrador de la empresa.
  2. El sistema valida que el slug no exista y que la contraseña cumpla la política.
  3. En una transacción, el sistema crea la `Empresa`, su `Suscripcion` y el usuario con rol
     ADMIN, y lo audita (RN03).
- **Alterno A1:** el slug o el email ya existen. El sistema responde 409 y no crea nada.

### CU02 Asignar / cambiar plan

- **Actor:** Administrador de plataforma.
- **Curso básico:** el Administrador elige el plan, la fecha de inicio y la de vencimiento. El
  sistema actualiza la `Suscripcion`. El cambio rige desde el request siguiente.
- **Alterno A1:** la empresa usa más sucursales de las que admite el plan nuevo. El sistema
  responde 409 con el uso actual y el tope.

### CU03 Configurar planes y límites

- **Actor:** Administrador de plataforma.
- **Curso básico:** el Administrador edita los topes y las funciones de un plan. El sistema
  guarda los cambios, que rigen para todas las empresas de ese plan.
- **Alterno A1:** bajar un tope por debajo del uso de una empresa no le borra nada. Solo le
  impide agregar más.

### CU17 Descargar datos para operar sin conexión

- **Actor:** Empleado.
- **Curso básico:**
  1. Con red, el Empleado abre «Vender sin conexión».
  2. El sistema pide `GET /sync/catalogo`. El paquete trae la sucursal autorizada, los productos
     y variantes con su existencia, las clientas y la sesión de caja abierta.
  3. El sistema lo guarda: en IndexedDB en la web y en las tablas `*_local` de SQLite en el
     móvil.
  4. A lo vendido offline que todavía no se confirmó, el sistema le vuelve a descontar la
     existencia.
- **Alterno A1:** no hay red y nunca se descargó. El sistema avisa que hay que conectarse una vez.

### CU18 Consultar catálogo sin conexión

- **Curso básico:** el sistema muestra productos, precios, tallas, colores y existencia conocida.
  Si no hay red, o si el paquete tiene más de 2 horas, avisa que la información puede estar
  desactualizada (RF20).

### CU20 Registrar venta de contado sin conexión

- **Actor:** Empleado con permiso de caja.
- **Curso básico:**
  1. El Empleado arma el ticket con el catálogo local y cobra el efectivo.
  2. El sistema genera un UUID v4 y guarda la operación como `REGISTRADA`. Guarda la empresa, la
     sucursal, el responsable, la fecha y hora (UTC), el detalle con el precio usado, el total
     con IVA y la forma de pago EFECTIVO (RN07, RN10).
  3. El sistema descuenta la existencia local y muestra «Solo en este equipo».
  4. Si hay red, el sistema la manda enseguida (CU22).
- **Regla 9.2:** cobrar el efectivo no confirma la venta. Queda pendiente hasta que el servidor
  la acepte (RN08).

### CU19 Registrar reserva sin conexión

Es igual que CU20, con la clienta de la cartera local, la fecha y la hora de visita. No tiene
total. La reserva compromete stock recién cuando el servidor la confirma.

- **Alterno A1, diferencia con CU12:** la reserva que registra el personal **nace CONFIRMADA**
  en el servidor (`sincronizacion/servicio.py`, inserción en `reserva`). No espera la
  confirmación del encargado, como la reserva de la clienta (CU12, que nace PENDIENTE), y pasa
  directo a la atención en el vestidor.

### CU21 Consultar operaciones locales y su estado

- **Curso básico:** el sistema lista las operaciones del usuario. Cada una muestra su estado:
  - «Solo en este equipo»;
  - «Enviada, sin respuesta»;
  - Confirmada, con el número de venta o reserva;
  - Rechazada o En conflicto, con el código y el motivo.
- **Alterno A1:** el usuario archiva las cerradas. Solo se quitan del equipo las confirmadas y
  las rechazadas (RN12). En el servidor quedan siempre: el encargado las ve en
  `/panel/sincronizacion` (CU24 Supervisar la sincronización de la sucursal).

### CU22 Sincronizar operaciones pendientes

Ver la secuencia `26` y la robustez `25`.

- **Actores:** Sistema de sincronización (vuelta de la red, cada 60 s) o Empleado (botón).
- **Precondición:** hay operaciones `REGISTRADA` o `ENVIADA` y el usuario está autenticado.
- **Curso básico:**
  1. El sistema toma las pendientes ordenadas por `registrada_en` y las marca `ENVIADA`.
  2. Las manda en lotes de hasta 50 a `POST /sync/operaciones`.
  3. El backend valida el token, la empresa, la sucursal, el responsable y el plan.
  4. Toma un candado sobre el id y verifica que no se haya procesado antes.
  5. Aplica la venta y su movimiento de inventario en una transacción.
  6. Responde `CONFIRMADA`, y el cliente guarda el resultado.
- **Alterno A1, falla de red:** la operación sigue `ENVIADA` con el aviso. Se reintenta a los
  30 s, 1 min, 2 min… hasta un máximo de 10 min. No se borra (RNF06).
- **Alterno A2, id ya procesado:** el backend devuelve el resultado guardado con
  `duplicada = true`. No se crea otra venta ni se descuenta stock dos veces (RN11). Se probó con 5
  reenvíos simultáneos.
- **Alterno A3, regla violada:** queda `CONFLICTO` con el código. Las causas son
  `STOCK_INSUFICIENTE`, `PRECIO_CAMBIADO`, `PRODUCTO_INACTIVO` y `SIN_CAJA_ABIERTA`.
- **Alterno A4, rechazo:** queda `RECHAZADA` con el motivo. Las causas son
  `SUSCRIPCION_VENCIDA`, `SIN_PERMISO`, `SUCURSAL_NO_AUTORIZADA`, `PRENDA_AJENA` y
  `TOTAL_INCONSISTENTE`.
- **Postcondición:** ninguna operación se pierde. Cada una queda con su estado y su resultado, y
  el servidor deja el log en `operacion_sync` (RNF10, sin datos de pago).

### CU23 Resolver conflicto de sincronización (extiende CU22)

- **Actores:** Empleado (solo reintentar lo propio) o Encargado / Administrador de empresa.
- **Curso básico:** el actor abre la operación en conflicto y elige una acción:
  - **Reintentar:** se usa después de abrir la caja o de que entró stock. El sistema la
    reprocesa tal cual.
  - **Aceptar el precio actual:** solo para `PRECIO_CAMBIADO`. El sistema la reprocesa con el
    precio que hoy tiene el servidor.
  - **Descartar:** la operación queda `RECHAZADA` con una nota, por ejemplo «se devolvió el
    efectivo».

### CU26 Solicitar reporte en lenguaje natural

Es la narrativa CU26 de `ICONIX_SEGUNDO_PARCIAL.md`, con este cambio: el plan que exige ahora es
**Profesional**.

- **Alterno A1:** plan Básico. El sistema responde 403 y la UI muestra el aviso, en la web y en
  el móvil.
- **Seguridad (10.4):** Claude no escribe SQL. Solo llama herramientas de un catálogo cerrado,
  con parámetros validados, y el filtro de empresa lo fuerza el backend.

### CU28 Consultar dashboard analítico / CU29 Entrenar y evaluar modelos de ML

Ver la robustez `28`.

- **CU29:**
  1. El sistema genera datos sintéticos con una semilla: demanda diaria por sucursal y tipo de
     prenda, y clientas con perfiles.
  2. Entrena un Random Forest de demanda y lo compara con una regresión lineal y con el
     pronóstico ingenuo «semana anterior». Usa partición temporal y `TimeSeriesSplit`, y mide
     MAE, RMSE, R² y MAPE.
  3. Entrena KMeans de clientas, eligiendo k por silueta y midiendo el ARI contra los perfiles.
  4. Guarda los modelos.
- **CU28:** el sistema aplica los modelos a las ventas reales de la empresa:
  - el pronóstico por sucursal y tipo;
  - los segmentos de la cartera;
  - los días atípicos con IsolationForest.

  Muestra indicadores, gráficos, las métricas y los hallazgos en texto.
- **Alterno A1:** plan Básico. El sistema responde 403.

## 3. Persistencia local del móvil (7.2 de la especificación)

Ver el diagrama `27`.

- **El paquete:** `sucursal_local`, `producto_local`, `variante_local` y `cliente_local`, con FK
  y `ON DELETE CASCADE`. Se reemplaza entero en una transacción en cada descarga.
- **Las operaciones:** venta y reserva comparten la tabla `operacion`, con un `CHECK` de estados,
  para no tener cuatro tablas casi iguales. Su detalle va en `operacion_detalle`, que guarda una
  foto del precio cobrado y a propósito **no** tiene FK al paquete. La última respuesta del
  servidor va en `resultado_sync`.
- **Cerrar sesión:** se vacían la caché y el paquete, pero nunca las operaciones (RN12, RNF03).

Lo prueban:

- `movil/test/operaciones_offline_test.dart` (10 tests sobre SQLite real);
- `movil/test_integracion/sincronizacion_en_vivo_test.dart`, el ciclo completo contra el backend:
  descargar, operar sin red, reiniciar, sincronizar, reenviar sin duplicar y conflicto.

# Paquetes de FashionStore

El código se organiza en **7 paquetes de negocio** y un **Núcleo** transversal. Un paquete es una
capacidad de negocio (alta cohesión) y cubre sus casos de uso en las cuatro capas del repositorio:
base de datos, backend, web y móvil. Cada uno de los 29 casos de uso del catálogo vigente
(CU01-CU29, `PARCIALES.md`) pertenece a un solo paquete. Los casos del primer parcial que no entran
en ese catálogo se nombran sin número, en la línea «Primer parcial».

Cada capa usa la convención de nombres de su ecosistema, pero el orden es el mismo:

| Paquete | Backend (`backend/app/modules/`) | Web (`frontend/src/app/{core,pages}/`) | Móvil (`movil/lib/{core,paginas}/`) |
|---|---|---|---|
| 1. Acceso y Organización | `acceso_y_organizacion/` | `acceso-y-organizacion/` | `acceso_y_organizacion/` |
| 2. Plataforma SaaS | `plataforma_saas/` | `plataforma-saas/` | `plataforma_saas/` |
| 3. Catálogo e Inventario | `catalogo_e_inventario/` | `catalogo-e-inventario/` | `catalogo_e_inventario/` |
| 4. Operación comercial | `operacion_comercial/` | `operacion-comercial/` | `operacion_comercial/` |
| 5. Operación sin conexión | `operacion_sin_conexion/` | `operacion-sin-conexion/` | `operacion_sin_conexion/` |
| 6. Relación con la clienta | `relacion_con_la_clienta/` | `relacion-con-la-clienta/` | `relacion_con_la_clienta/` |
| 7. Inteligencia de negocio | `inteligencia_de_negocio/` | `inteligencia-de-negocio/` | `inteligencia_de_negocio/` |
| Núcleo | `core/` (+ `core/notificaciones/`) | `core/nucleo/` y `shared/` | `core/nucleo/`, `core/*.dart` y `compartido/` |

Dentro de cada carpeta de paquete queda un subdirectorio por módulo de dominio
(`operacion_comercial/ventas/router.py`, `core/operacion-comercial/ventas/ventas.service.ts`, etc.).

## 1. Acceso y Organización

CU06 Gestionar sucursales y cajas.

Primer parcial: iniciar sesión, registrarse, cambiar contraseña, gestionar usuarios, gestionar roles
y permisos, consultar bitácora de auditoría.

- **Backend:** `usuarios` (incluye `/auth`), `sucursales`, `auditoria`.
- **Web y móvil, dominios:** `auth`, `usuarios`, `sucursales`, `auditoria`.
- **Web, pantallas:** `login`, `registro`, `cambiar-password`, `panel-usuarios`, `panel-sucursales`,
  `panel-auditoria`. **Móvil:** `login`, `registro`, `cambiar_password`, `cuenta`, `panel` (menú de
  gestión), `panel_usuarios`, `panel_sucursales`, `panel_auditoria`.
- **Base de datos:** `rol`, `permiso`, `rol_permiso`, `usuario`, `perfil_cliente`, `sesion_token`,
  `sucursal`, `empleado`, `auditoria`.

## 2. Plataforma SaaS

CU01 Gestionar empresas, CU02 Asignar o cambiar el plan, CU03 Configurar planes y límites, CU04
Consultar suscripción y plan contratado, CU05 Renovar suscripción.

- **Backend:** `saas`. **Web y móvil, dominio:** `saas`.
- **Web, pantallas:** `panel-empresas`, `panel-suscripcion`. **Móvil:** `panel_suscripcion`.
- **Base de datos:** `pago_suscripcion`. Las tablas raíz `empresa`, `plan` y `suscripcion` las lee
  el Núcleo (`core/tenant.py`, `core/plan.py`), pero este paquete es el que las administra.

## 3. Catálogo e Inventario

CU09 Registrar recepción de mercadería, CU10 Gestionar inventario, CU11 Sugerir traspasos según la
demanda.

Primer parcial: consultar catálogo, gestionar categorías y marcas, gestionar promociones,
gestionar proveedores.

- **Backend:** `catalogo` (vitrina y admin), `proveedores`, `inventario`, `recepciones`, `traspasos`.
- **Web y móvil, dominios:** `catalogo`, `proveedores`, `inventario`, `recepciones`, `traspasos`.
- **Web, pantallas:** `tienda`, `producto-detalle`, `panel-catalogo`, `panel-proveedores`,
  `panel-recepciones`, `panel-inventario`, `panel-traspasos`. **Móvil:** `tienda`,
  `producto_detalle`, `panel_catalogo`, `panel_proveedores`, `panel_recepciones`,
  `panel_inventario`, `panel_traspasos`.
- **Base de datos:** `talla`, `color`, `proveedor`, `categoria`, `marca`, `temporada`, `coleccion`,
  `producto`, `producto_variante`, `producto_imagen`, `promocion`, `inventario`,
  `movimiento_inventario`, `recepcion`, `recepcion_detalle`, `traspaso`, `traspaso_detalle`;
  vistas `v_disponibilidad`, `v_stock_global`, `v_existencias_consolidadas`; funciones `fn_mover_inventario` (único punto de
  escritura de stock), `fn_confirmar_recepcion` y `fn_traspaso_stock`.

## 4. Operación comercial

CU12 Reservar prendas, CU13 Pagar con pasarela electrónica, CU14 Registrar venta presencial, CU15
Registrar devolución, CU16 Gestionar cambios de prenda.

Primer parcial: consultar y cancelar reservas, gestionar carrito, comprar en línea, abrir y cerrar
caja, verificar pagos pendientes, entregar pedido de retiro, atender reservas, consultar historial
de compras, gestionar direcciones, despachar envíos.

Los traspasos entre sucursales están en Catálogo e Inventario (CU10 y CU11).

Es el paquete más grande; internamente se distingue en subpaquetes:

| Subpaquete | Módulos (backend) | Dominios (web y móvil) |
|---|---|---|
| Reservas | `reservas` | `reservas` |
| Compra y pago | `carrito`, `ventas`, `pagos` | `carrito`, `ventas` |
| Caja | `caja` | `caja` |
| Entregas | `direcciones`, `envios` | `direcciones`, `envios` |
| Devoluciones y cambios | `devoluciones` | `devoluciones` |

- **Web, pantallas:** `reservar`, `mis-reservas`, `atender-reservas`, `carrito`, `compra`,
  `pago-simulado`, `mis-compras`, `caja`, `mis-direcciones`, `panel-devoluciones`. **Móvil:** las
  mismas con sufijo `_pagina`.
- **Base de datos:** `reserva`, `reserva_detalle`, `reserva_historial`, `carrito`, `carrito_item`,
  `venta`, `venta_detalle`, `pago`, `evento_pasarela`, `comprobante`, `caja`, `sesion_caja`,
  `direccion`, `envio`, `envio_evento`, `devolucion`, `devolucion_detalle`; vista
  `v_ventas_diarias`; funciones y triggers `fn_venta_descuenta_stock`,
  `fn_reserva_compromete_stock`, `fn_reserva_historial`, `fn_expirar_reservas`,
  `fn_total_efectivo_sesion`, `fn_devolucion_stock`, `fn_cotizar_envio`, `fn_envio_historial`.

## 5. Operación sin conexión

CU17 Descargar datos para operar sin conexión, CU18 Consultar catálogo sin conexión, CU19 Registrar
reserva sin conexión, CU20 Registrar venta de contado sin conexión, CU21 Consultar operaciones
locales, CU22 Sincronizar operaciones pendientes, CU23 Resolver conflicto de sincronización, CU24
Supervisar la sincronización de la sucursal.

- **Backend:** `sincronizacion` (`/sync`). **Web:** dominios `sincronizacion` y `offline` (caché y
  cola en IndexedDB, interceptor), pantallas `venta-offline` y `panel-sincronizacion`; además la
  PWA (`ngsw-config.json`, `manifest.webmanifest`). **Móvil:** dominios `sincronizacion` y
  `offline` (SQLite), pantalla `venta_offline`.
- **Base de datos:** `operacion_sync`.

## 6. Relación con la clienta

CU07 Elegir tienda, CU08 Gestionar clientas de la empresa. CU07 se apoya en `/saas/tiendas`
(paquete Plataforma SaaS) y en el header `X-Empresa` (Núcleo).

Primer parcial: usar vestidor virtual (solo móvil), recibir recomendaciones, conversar con el
asistente virtual.

- **Backend:** `recomendaciones`, `asistente`, `clientes`. **Web y móvil, dominios:**
  `recomendaciones`, `asistente`, `clientes`.
- **Web, pantallas:** `asistente`, `panel-clientes`. **Móvil:** `asistente`, `panel_clientes`,
  `vestidor_virtual`, `visor_3d`.
- **Base de datos:** `cliente_perfil_tenant`.

## 7. Inteligencia de negocio

CU25 Consultar pérdidas por sucursal, CU26 Solicitar reporte en lenguaje natural, CU27 Exportar
reporte a Excel o PDF, CU28 Consultar dashboard analítico, CU29 Entrenar y evaluar modelos de ML.

Primer parcial: consultar reportes e indicadores.

- **Backend:** `reportes`, `analitica` (scikit-learn). **Web:** dominios `reportes` y `analitica`,
  pantallas `panel-reportes` y `panel-analitica`. **Móvil:** dominio `reportes`, pantalla
  `panel_reportes` (sin analítica).
- **Base de datos:** sin tablas propias; solo lee de los demás paquetes.

## Núcleo (transversal)

Sin casos de uso del catálogo vigente. Primer parcial: consultar notificaciones.

- **Backend:** `app/core/` (`config`, `db`, `security`, `deps`, `tenant`, `plan`, `auditoria`,
  `ruteo`, `jobs`, `mutex`, `media`) y `app/core/notificaciones/` (la escriben siete módulos).
- **Web:** `core/nucleo/` (`tenant`, `notificaciones`) y `shared/` (componentes, validaciones, voz,
  mapa, shell del panel).
- **Móvil:** `core/nucleo/` (`tenant`, `notificaciones`), `core/api.dart`, `config.dart`,
  `errores.dart`, `tema.dart`, `compartido/` y la pantalla `paginas/nucleo/notificaciones`.
- **Base de datos:** `empresa`, `plan`, `suscripcion`, `configuracion`, `notificacion`.

## Dependencias entre paquetes

```
Núcleo  <--  todos los paquetes
2 SaaS  --> 1 Acceso            (alta de administrador, sucursal, caja y empleado)
3 Catálogo e Inventario --> 1
4 Operación comercial   --> 3, 1, 2   (2: el webhook de Stripe también cobra suscripciones)
5 Sin conexión          --> 4, 3, 1
6 Relación con la clienta  --> 3, 4, 1   (solo lectura)
7 Inteligencia de negocio  --> 3, 4, 1   (solo lectura)
1 Acceso --> 4   (única flecha de vuelta, solo lectura: no desactivar usuarios o sucursales con
                  ventas, reservas o caja abierta)
```

Los planes se aplican desde el Núcleo (`core/plan.py`): `requiere_funcion_plan` protege reportes con
IA, analítica, perfil de clientas, traspasos y operación sin conexión, y `exigir_limite` topa
sucursales, personal y cajas.

## Dónde va el código nuevo

1. Elegir el paquete según el caso de uso (CU) que se implementa.
2. Backend: `backend/app/modules/<paquete>/<modulo>/{router.py,schemas.py}` y registrar el router en
   `app/main.py`. Importar siempre con la ruta completa
   (`from app.modules.operacion_comercial.ventas.router import ...`).
3. Web: `core/<paquete>/<dominio>/` para servicios y modelos, `pages/<paquete>/<pantalla>/` para la
   pantalla, y la ruta en `app.routes.ts`.
4. Móvil: `lib/core/<paquete>/<dominio>/` y `lib/paginas/<paquete>/<nombre>_pagina.dart`, y la ruta
   en `lib/rutas.dart`.
5. Base de datos: tablas y funciones en `db/01_schema.sql` y `db/02_logica.sql` (se mantienen como
   un solo juego de scripts ordenado, porque Postgres los ejecuta en secuencia y hay claves foráneas
   entre paquetes); anotar el paquete en esta tabla.

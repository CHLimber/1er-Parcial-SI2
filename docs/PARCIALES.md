# FashionStore: catálogo de casos de uso del segundo parcial

Este archivo fija el **catálogo de casos de uso que usa la documentación del segundo parcial**:
29 casos, CU01-CU29. Es el único catálogo vigente. Cualquier otro número de caso de uso que
aparezca en diagramas, narrativas o código anteriores pertenece a una numeración vieja; la
sección 6 dice a qué caso de este catálogo corresponde.

Última actualización: 22/10/2026.

Fuentes:

- Primer parcial: `Examen1-Ecommerce-Si2-s2-26.pdf` (consigna), `ducumentacion.docx`
  (CU01-CU19 entregados), `docs/uml/07_casos_de_uso.puml` y `movil/README.md`.
- Segundo parcial: `Examen Parcial-2 - Sistemas 2 - S2-2026.pdf`, `docs/uml/10_*.puml` y
  `24_*.puml`, `ICONIX_SEGUNDO_PARCIAL.md`, `ICONIX_SAAS_MULTITENANT.md` y los endpoints del
  backend (`app/modules/**/router.py`).

Reglas:

1. **Solo estos 29 casos de uso existen para el documento del segundo parcial.** Son los 22
   casos nuevos del segundo parcial más los 7 del primer parcial que el segundo afecta o de los
   que depende. Los demás casos del primer parcial no se documentan (sección 4.3).
2. **Lo entregado no se reescribe.** El `ducumentacion.docx` del primer parcial (defendido el
   22/09/2026) conserva su numeración propia. Como los números CU01-CU20 se repiten entre ese
   docx y este catálogo, en el documento del segundo parcial "CUxx" refiere siempre a este
   catálogo, y para citar el docx se escribe "CUxx del primer parcial".
3. Criterio para decidir qué es un caso de uso: **un actor, un objetivo que le aporta valor, una
   sesión**. Lo que es un paso, una validación o una regla de negocio queda como `include`, como
   curso alterno o como regla (sección 2), no como caso de uso con número.
4. **Numeración en el código y en las notas del repositorio.** Los comentarios de los paquetes
   Plataforma SaaS, Operación sin conexión y la analítica de Inteligencia de negocio usan este
   catálogo. Los comentarios de los módulos del primer parcial, `CLAUDE.md`, `PENDIENTES.txt` y
   los diagramas `01`-`08` usan la numeración del docx del primer parcial (sección 6.1), porque la
   mayoría de esos casos no tiene número en este catálogo. Donde un comentario del Núcleo cita un
   caso del primer parcial, lo dice ("CU13 del primer parcial").

---

## 1. Catálogo vigente (CU01-CU29)

### 1.1 Actores

| Actor | Rol en el código | Equivale en el primer parcial a |
|---|---|---|
| Administrador de plataforma | `SUPERADMIN` (no pertenece a ninguna empresa) | No existía |
| Administrador de empresa | `ADMIN` del tenant | Administrador |
| Encargado (gerente de sucursal) | `ENCARGADO` | Encargado de sucursal |
| Empleado | `CAJERO`, `VENDEDOR` | Cajero |
| Clienta | `CLIENTE` (cuenta de la plataforma; elige la tienda con `X-Empresa`) | Cliente |
| Temporizador / vuelta de la red | dispara la sincronización | No existía |
| Claude API | servicio externo | Servicio de IA |
| Stripe | servicio externo | Sistema de pagos |

El tenant es la **empresa**, no la sucursal (decisión del 18/10/2026; ver
`ICONIX_SAAS_MULTITENANT.md`). **Proveedor** queda fuera de alcance: no entra al sistema, el
administrador lo registra y el encargado recibe su mercadería.

### 1.2 Casos de uso

Origen: **1P** = caso del primer parcial que el segundo modifica o del que depende. **2P** = caso
nuevo del segundo parcial.

| Nº | Caso de uso | Actor(es) | Relación | Origen | Desafío o motivo |
|---|---|---|---|---|---|
| **Plataforma SaaS** ||||||
| CU01 | Gestionar empresas (registrar con su administrador, editar, suspender) | Admin. plataforma | - | 2P | VI (9.3) |
| CU02 | Asignar o cambiar el plan de una empresa (fecha de inicio y vencimiento) | Admin. plataforma | - | 2P | VI (9.5) |
| CU03 | Configurar planes y límites | Admin. plataforma | - | 2P | VI (9.4) |
| CU04 | Consultar suscripción y plan contratado | Admin. empresa, Admin. plataforma | - | 2P | VI (9.3, 9.5) |
| CU05 | Renovar suscripción (Stripe o pago manual simulado) | Admin. empresa, Admin. plataforma, Stripe | - | 2P | VI (9.5). Reusa la integración de CU13 |
| **Acceso y organización** ||||||
| CU06 | Gestionar sucursales y cajas | Admin. empresa | - | 1P | El plan limita las sucursales activas (2 en Básico, 10 en Profesional) y las cajas |
| **Relación con la clienta** ||||||
| CU07 | Elegir tienda | Clienta | - | 2P | VI (9.6) |
| CU08 | Gestionar clientas de la empresa | Empleado, Admin. empresa | - | 2P | VI (9.1) |
| **Catálogo e inventario** ||||||
| CU09 | Registrar recepción de mercadería | Encargado | - | 1P | Inventario aislado por empresa |
| CU10 | Gestionar inventario (productos y variantes, existencias consolidadas, kardex, ajustes y traspasos entre sucursales) | Encargado, Admin. empresa | - | 1P | Fuente del paquete de CU17; contra este stock se detectan los conflictos de CU22 y CU23. Sus mermas alimentan CU25 |
| CU11 | Sugerir traspasos según la demanda | Encargado | extend de CU10 | 2P | IV (7.2, aporte propio) |
| **Operación comercial** ||||||
| CU12 | Reservar prendas | Clienta | - | 1P | CU19 usa sus mismas reglas: compromete stock y vence |
| CU13 | Pagar con pasarela electrónica (Stripe o QR) | Clienta, Stripe | - | 1P | Stripe se reusa en CU05; los pagos quedan aislados por empresa |
| CU14 | Registrar venta presencial (incluye emitir comprobante) | Empleado | - | 1P | CU20 es su variante sin conexión; el servidor la valida con las mismas reglas |
| CU15 | Registrar devolución con reintegro | Encargado | - | 1P | CU16 es una devolución más una venta nueva vinculada |
| CU16 | Gestionar cambios de prenda (talla o color, plazo, nota de devolución, cambios del mes) | Encargado, Admin. empresa | - | 2P | IV (7.2). Los permisos `devoluciones.*` son solo de ADMIN y ENCARGADO |
| **Operación sin conexión** ||||||
| CU17 | Descargar datos para operar sin conexión | Empleado | - | 2P | II (5.2), III (6.2) |
| CU18 | Consultar catálogo sin conexión (avisa si está desactualizado) | Empleado | - | 2P | II (5.3 1-2), III (6.2) |
| CU19 | Registrar reserva sin conexión | Empleado | - | 2P | II (5.3 3), III (6.2) |
| CU20 | Registrar venta de contado sin conexión | Empleado | - | 2P | II (5.3 4), III, IV (7.2) |
| CU21 | Consultar operaciones locales y su estado (y archivar las cerradas) | Empleado | - | 2P | II (5.3 5-6), III (6.2) |
| CU22 | Sincronizar operaciones pendientes | Empleado, Temporizador | - | 2P | II (5.4), III (6.4) |
| CU23 | Resolver conflicto de sincronización | Empleado, Encargado, Admin. empresa | extend de CU22 [conflicto o rechazo] | 2P | Obj. específico 9 |
| CU24 | Supervisar la sincronización de la sucursal | Encargado, Admin. empresa | - | 2P | III (6.2), RNF10 |
| **Inteligencia de negocio** ||||||
| CU25 | Consultar pérdidas por sucursal | Encargado, Admin. empresa | - | 2P | IV (7.2, aporte propio) |
| CU26 | Solicitar reporte en lenguaje natural (texto o voz; tabla o gráfico) | Encargado, Admin. empresa, Claude API | - | 2P | V (8.1-8.3) |
| CU27 | Exportar reporte a Excel o PDF | Encargado, Admin. empresa | extend de CU26 | 2P | V (8.1, 8.5) |
| CU28 | Consultar dashboard analítico | Encargado, Admin. empresa | - | 2P | V (8.4) |
| CU29 | Entrenar y evaluar modelos de ML (datos sintéticos, métricas) | Admin. plataforma | - | 2P | V (8.4, 8.5) |

Total: 22 casos 2P y 7 casos 1P.

---

## 2. Reglas y pasos que no son casos de uso

| Regla o paso | Dónde queda |
|---|---|
| Instalar la PWA | Requisito (examen 5.2, RNF08). La instalación la hace el navegador; el sistema solo tiene que ser instalable |
| El token lleva la empresa | Regla de negocio (cap. II, 2.4) y RNF02. Es el cambio del inicio de sesión, que no se documenta como caso |
| Aislamiento por empresa (404 en recursos ajenos) | Regla transversal (RNF02) |
| Verificar límite del plan | Regla en CU06 (sucursales y cajas) y en CU02. El tope de personal se menciona en CU01 (al registrar la empresa se crea su administrador) |
| Validar plan Profesional | Precondición de CU26 y CU28 |
| Suscripción vencida (402) | Regla transversal; en CU22, lo registrado antes del vencimiento se acepta |
| Caja abierta | Precondición de CU14 y CU20: en el mostrador no se cobra sin caja abierta, y el backend deja en CONFLICTO `SIN_CAJA_ABIERTA` la venta sin conexión que llega sin una sesión de caja abierta en esa sucursal (`sincronizacion/servicio.py`, `_sesion_de_caja`); se resuelve con CU23 (reintentar después de abrir la caja) |
| Asignar identificador único y estado local | Paso de CU19 y CU20 |
| Validar tenant y suscripción, verificar idempotencia | Pasos de CU22 |
| Manejar solicitud ambigua o no soportada | Curso alterno de CU26 |
| Dictar la solicitud por voz | Variante de entrada de CU26. Implementado, pero **no figura en ningún diagrama** |
| Imprimir nota de devolución, consultar cambios del mes | Pasos de CU16 |

**Diferencia de regla entre CU12 y CU19.** La reserva de la clienta (CU12) nace PENDIENTE y la
confirma el encargado. La que registra el personal sin conexión (CU19) **nace CONFIRMADA**
(`servicio.py`, inserción en `reserva`) y va directo a la atención en el vestidor. Se escribe
como curso alterno de CU19.

---

## 3. Código y estado de la narrativa

Estado: **OK** = implementado y con narrativa vigente. **Actualizar** = la narrativa existe pero
asume tenant = sucursal, es la del docx del primer parcial sin la nota de cambio, o le falta una
parte. **Falta** = no hay narrativa.

| CU | Código | Narrativa |
|---|---|---|
| CU01 | `POST/PUT /saas/empresas`, `PATCH /saas/empresas/{id}/estado` | OK (registrar); Falta (editar, suspender) |
| CU02 | `PUT /saas/empresas/{id}/plan` | OK |
| CU03 | `PUT /saas/planes/{codigo}` | OK |
| CU04 | `GET /saas/suscripcion`, `GET /saas/suscripciones`, `GET /saas/pagos` | Actualizar |
| CU05 | `POST /saas/suscripcion/checkout`, `POST /saas/pagos/verificar`, `POST /saas/suscripciones/{empresa_id}/pago-manual` | Actualizar |
| CU06 | `/admin/sucursales`, `/admin/sucursales/{id}/cajas` | Actualizar (docx: CU12 del primer parcial) |
| CU07 | `GET /saas/tiendas`, header `X-Empresa` (`core/nucleo/tenant/tienda.ts`, `core/nucleo/tenant/tienda.dart`) | Falta |
| CU08 | `/clientes`, `PUT /clientes/{id}/perfil` | Actualizar |
| CU09 | `/recepciones`, `POST /recepciones/{id}/confirmar` | Actualizar (docx: CU09 del primer parcial) |
| CU10 | `/admin/catalogo/productos`, `/inventario/variantes`, `/inventario/{id}/kardex`, `POST /inventario/ajustes`, `/traspasos`, `GET /reportes/existencias` | Falta (el docx solo tiene la parte de productos, dentro de su CU10) |
| CU11 | `GET /traspasos/sugerencias` | Actualizar |
| CU12 | `POST /reservas`, `POST /reservas/{id}/cancelar` | Actualizar (docx: CU04 del primer parcial) |
| CU13 | `POST /ventas/checkout`, `POST /pagos/webhook/stripe`, `POST /pagos/qr/{id}/informar` | Actualizar (docx: CU06 del primer parcial) |
| CU14 | `POST /ventas/pos` | Actualizar (docx: CU07 del primer parcial) |
| CU15 | `/devoluciones`, `POST /devoluciones/{id}/aprobar` | Falta |
| CU16 | `POST /devoluciones`, `GET /devoluciones/variantes-cambio`, `POST /devoluciones/{id}/cambio`, `GET /devoluciones/{id}/nota`, `GET /devoluciones/cambios-mes` | OK |
| CU17 | `GET /sync/catalogo`, `ngsw-config.json`, manifest | OK |
| CU18 | web `/offline` (IndexedDB), móvil `venta_offline_pagina.dart` (SQLite) | OK |
| CU19 | `POST /sync/operaciones` (tipo RESERVA) | OK; agregar el curso alterno de la sección 2 |
| CU20 | `POST /sync/operaciones` (tipo VENTA) | OK |
| CU21 | almacenamiento local (IndexedDB / SQLite `operacion`, `resultado_sync`) | OK |
| CU22 | `POST /sync/operaciones` | OK |
| CU23 | `POST /sync/operaciones/{id}/resolver` | OK |
| CU24 | `GET /sync/operaciones`, `/panel/sincronizacion` | OK |
| CU25 | `GET /reportes/perdidas` | OK |
| CU26 | `POST /reportes/consulta-ia`, `shared/voz.ts`, página `reportes` | OK (consulta); Falta (visualización) |
| CU27 | página `reportes` | Falta |
| CU28 | `GET /analitica/dashboard` | OK |
| CU29 | `POST /analitica/entrenar`, `GET /analitica/modelo`, `GET /analitica/datos-sinteticos` | OK |

Las narrativas de los casos 1P (CU06, CU09, CU10, CU12 a CU15) llevan una sección "Qué cambia en
el segundo parcial", con lo que dice la columna "Desafío o motivo" de 1.2.

---

## 4. Qué se deja afuera del documento

### 4.1 Cómo se llegó a los 29

El 22/10/2026 se revisó el primer parcial con el criterio de la regla 3 y salieron 39 casos
(sección 6.2), más 22 nuevos del segundo parcial (sección 6.3). Para el documento del segundo
parcial se conservaron los 22 nuevos y, del primer parcial, solo los que el segundo afecta o de
los que depende: eran 9, y quedaron en 7 porque ajustar inventario, traspasar inventario y
consultar existencias (que ya absorbía productos y variantes) se fusionaron en CU10.

### 4.2 Casos del primer parcial que no se documentan y dónde se cubre su cambio

| Caso del primer parcial | Dónde se cubre lo que cambia en el segundo |
|---|---|
| Iniciar sesión | Regla "el token lleva la empresa" (sección 2) |
| Usuarios, roles y permisos | Son de cada empresa y tienen tope de personal: se menciona en CU01 |
| Consultar catálogo | Elegir la tienda con `X-Empresa`: CU07 |
| Abrir y cerrar caja | Precondición "caja abierta" de CU14 y CU20 |
| Reportes e indicadores; reporte con IA por voz | Los reportes del segundo parcial son CU25 y CU26 |
| Atender reserva, confirmar o rechazar reserva | Curso alterno de CU19 (sección 2) |
| El resto (registro, carrito, compra, envíos, RA, recomendaciones, chatbot, auditoría, notificaciones, etc.) | Solo heredan el filtro por empresa del backend |

### 4.3 Limitaciones del primer parcial para el capítulo I

- **Proveedor** fuera de alcance (sección 1.1).
- **Tallas y colores:** no tienen CRUD, solo se leen las del seed (`/admin/catalogo/referencias`).
- **Temporadas y colecciones:** no se pueden crear ni editar (RF23 del primer parcial lo pide).

---

## 5. Qué falta en la documentación del segundo parcial

Sigue el índice del examen (capítulos II y III).

**Diagramas en draw.io (22/10/2026).** Ya están hechos con CU01-CU29, en
`ducumentacion/UML 2.5/`: casos de uso general, dominio, clases de diseño, despliegue,
arquitectura (componentes por capas) y secuencia, robustez y comunicación de los 29 casos. Esos
`.drawio` reemplazan a los `.puml` de `docs/uml/` para el documento del segundo parcial. Los
puntos 1, 3 (diagramas) y 6 de esta lista quedan cubiertos por ellos.

1. **2.5 Diagrama de casos de uso.** Rehacer un solo diagrama con CU01-CU29, con los 7 casos 1P
   marcados como modificados. Los diagramas 10 y 24 quedan como historia.
2. **2.6 Especificaciones.** Escribir las que dicen "Falta" en la sección 3 (CU01 editar y
   suspender, CU07, CU10, CU15, CU26 visualización, CU27) y actualizar las que dicen
   "Actualizar".
3. **Renumerar los diagramas** a CU01-CU29 con las tablas de la sección 6: los `10`-`19` usan la
   numeración de 6.6 y los `24`-`28`, la de 6.5. Ya están renumerados (22/10/2026)
   `ICONIX_SEGUNDO_PARCIAL.md`, `ICONIX_SAAS_MULTITENANT.md`, `PAQUETES.md`, `uml/README.md` y
   los comentarios del código de los paquetes del segundo parcial (regla 4). El módulo
   `traspasos` se movió a `catalogo_e_inventario/` en backend, web y móvil (22/10/2026), así que
   cada caso de uso vive en el paquete de su código.
4. **Corregir el diagrama 10.** Tiene `Admin --|> Encargado`, y eso contradice que el SUPERADMIN
   no pertenece a ninguna empresa.
5. **Decidir si CU16 (cambio de prenda) funciona sin conexión.** El diagrama 24 lo pone en el
   paquete offline, pero las operaciones offline solo son reserva y venta (CU19 y CU20). Se saca
   del paquete o se implementa offline, y la decisión se anota.
6. **3.1 a 3.5.** Ya existen el modelo de dominio (`23`), las robusteces (`11`-`16`, `25`, `28`),
   las secuencias (`17`, `18`, `26`) y el modelo SQLite (`27`). Falta revisar que usen la
   numeración vigente, y agregar las robusteces de los casos 1P que no tienen (por lo menos
   CU10, CU14 y CU15). El diagrama de clases de diseño (`19`) es del 14/10, con tenant =
   sucursal: hay que revisarlo.
7. **3.6 Interfaces.** No hay un documento propio todavía.
8. **Capítulo I, alcance y limitaciones.** Anotar lo de la sección 4.3.

---

## 6. Historial: numeraciones anteriores

**Ninguno de los números de esta sección es vigente.** Se conservan para poder rastrear los
documentos, diagramas y comentarios que todavía los usan. La columna "Ahora" da el caso del
catálogo vigente; "-" significa que no se documenta en el segundo parcial.

### 6.1 Primer parcial tal como se entregó (`ducumentacion.docx`, congelado)

| CU entregado | Nombre | Ahora |
|---|---|---|
| CU01 | Iniciar sesión | - (regla, sección 2) |
| CU02 | Registrarse | - |
| CU03 | Consultar catálogo | - (cambio cubierto por CU07) |
| CU04 | Reservar prendas | CU12 |
| CU05 | Comprar por web/app | - |
| CU06 | Procesar y confirmar pago electrónico | CU13 (la verificación del cajero queda afuera) |
| CU07 | Registrar venta presencial | CU14 |
| CU08 | Atender reserva | - (curso alterno de CU19) |
| CU09 | Registrar recepción de mercadería | CU09 |
| CU10 | Gestionar catálogo (incluye promociones) | CU10 (solo productos y variantes) |
| CU11 | Gestionar proveedores | - |
| CU12 | Gestionar sucursales | CU06 |
| CU13 | Gestionar usuarios y roles | - (mencionado en CU01) |
| CU14 | Consultar historial de reservas y compras | - |
| CU15 | Consultar reportes e indicadores | - (su extend "consolidado de existencias" pasa a CU10) |
| CU16 | Usar vestidor virtual (RA) | - |
| CU17 | Recibir recomendaciones de IA | - |
| CU18 | Asistir al cliente vía chatbot | - |
| CU19 | Consultar bitácora de auditoría | - |
| CU20 | Entrega a domicilio | - |
| sin número | Ajustar stock | CU10 |

### 6.2 Primer parcial revisado (CU01-CU39, 22/10/2026)

Análisis previo a este catálogo, con el criterio de la regla 3.

| Revisado | Caso de uso | Actor | Entregado | Ahora |
|---|---|---|---|---|
| CU01 | Iniciar y cerrar sesión | Todos | CU01 | - |
| CU02 | Registrarse | Cliente | CU02 | - |
| CU03 | Cambiar contraseña | Todos | — | - |
| CU04 | Gestionar usuarios del personal | Administrador | CU13 (parte) | - |
| CU05 | Gestionar roles y permisos | Administrador | CU13 (parte) | - |
| CU06 | Gestionar sucursales y cajas | Administrador | CU12 | CU06 |
| CU07 | Consultar bitácora de auditoría | Administrador | CU19 | - |
| CU08 | Gestionar productos y variantes | Administrador | CU10 (parte) | CU10 |
| CU09 | Gestionar categorías, marcas, tallas y colores | Administrador | CU10 (parte) | - |
| CU10 | Gestionar temporadas y colecciones | Administrador | — | - (no implementado) |
| CU11 | Gestionar promociones | Administrador | CU10 (parte) | - |
| CU12 | Gestionar proveedores | Administrador | CU11 | - |
| CU13 | Registrar recepción de mercadería | Encargado | CU09 | CU09 |
| CU14 | Ajustar inventario | Encargado | "Ajustar stock" | CU10 |
| CU15 | Traspasar inventario entre sucursales | Encargado | — | CU10 |
| CU16 | Consultar existencias consolidadas y kardex | Administrador, Encargado | extend de CU15 | CU10 |
| CU17 | Consultar catálogo y disponibilidad | Cliente | CU03 | - |
| CU18 | Usar vestidor virtual (RA) | Cliente | CU16 | - |
| CU19 | Reservar prendas | Cliente | CU04 | CU12 |
| CU20 | Consultar y cancelar reservas | Cliente | CU14 (parte) | - |
| CU21 | Gestionar carrito | Cliente | — | - |
| CU22 | Comprar en línea | Cliente | CU05 | - |
| CU23 | Pagar con pasarela electrónica | Cliente, Sistema de pagos | CU06 (parte) | CU13 |
| CU24 | Gestionar direcciones de entrega | Cliente | CU20 (parte) | - |
| CU25 | Consultar historial de compras y seguimiento del envío | Cliente | CU14 (parte) | - |
| CU26 | Recibir recomendaciones | Cliente | CU17 | - |
| CU27 | Conversar con el asistente virtual | Cliente, Servicio de IA | CU18 | - |
| CU28 | Consultar notificaciones | Todos | sin número | - |
| CU29 | Abrir y cerrar caja | Cajero | include de CU07 | - (precondición de CU14 y CU20) |
| CU30 | Registrar venta presencial | Cajero | CU07 | CU14 |
| CU31 | Verificar pagos pendientes | Cajero | CU06 (parte) | - |
| CU32 | Entregar pedido de retiro en tienda | Cajero | — | - |
| CU33 | Gestionar solicitudes de reserva | Encargado | CU08 (parte) | - |
| CU34 | Atender a la clienta en el vestidor | Encargado | CU08 (parte) | - |
| CU35 | Despachar envíos a domicilio | Encargado | "Gestionar envíos" | - |
| CU36 | Registrar devolución con reintegro | Encargado | — | CU15 |
| CU37 | Consultar reportes e indicadores | Administrador, Encargado | CU15 | - |
| CU38 | Generar reporte con IA por voz | Administrador, Encargado | extend de CU15 | - |
| CU39 | Liberar reservas y pedidos vencidos | Temporizador | — | - |

### 6.3 Segundo parcial CU40-CU61 (22/10/2026)

| Antes | Caso de uso | Ahora |
|---|---|---|
| CU40 | Gestionar empresas | CU01 |
| CU41 | Asignar o cambiar el plan | CU02 |
| CU42 | Configurar planes y límites | CU03 |
| CU43 | Consultar suscripción y plan contratado | CU04 |
| CU44 | Renovar suscripción | CU05 |
| CU45 | Elegir tienda | CU07 |
| CU46 | Gestionar clientas de la empresa | CU08 |
| CU47 | Descargar datos para operar sin conexión | CU17 |
| CU48 | Consultar catálogo sin conexión | CU18 |
| CU49 | Registrar reserva sin conexión | CU19 |
| CU50 | Registrar venta de contado sin conexión | CU20 |
| CU51 | Consultar operaciones locales | CU21 |
| CU52 | Sincronizar operaciones pendientes | CU22 |
| CU53 | Resolver conflicto de sincronización | CU23 |
| CU54 | Supervisar la sincronización | CU24 |
| CU55 | Gestionar cambios de prenda | CU16 |
| CU56 | Sugerir traspasos según la demanda | CU11 |
| CU57 | Consultar pérdidas por sucursal | CU25 |
| CU58 | Solicitar reporte en lenguaje natural | CU26 |
| CU59 | Exportar reporte | CU27 |
| CU60 | Consultar dashboard analítico | CU28 |
| CU61 | Entrenar y evaluar modelos de ML | CU29 |

### 6.4 Segundo parcial CU21-CU38 (usado en `PAQUETES.md`)

| Antes | Nombre | Ahora |
|---|---|---|
| CU21 | Registrar empresa | CU01 |
| CU22 | Gestionar suscripción | CU02 (asignar o cambiar plan), CU04 (consultar), CU05 (renovar) |
| CU23 | Configurar planes y límites | CU03 |
| CU24 | Gestionar clientas de la empresa | CU08 |
| CU25 | Preparar uso offline (instalar PWA y descargar catálogo) | CU17 (la instalación pasa a requisito, sección 2) |
| CU26 | Consultar catálogo offline | CU18 |
| CU27 | Registrar reserva (online u offline) | CU19 |
| CU28 | Registrar venta de contado (online u offline) | CU20 |
| CU29 | Consultar operaciones pendientes y resultado de la sincronización | CU21 (local), CU24 (servidor) |
| CU30 | Sincronizar operaciones pendientes | CU22 |
| CU31 | Resolver conflicto de sincronización | CU23 |
| CU32 | Gestionar cambios de prenda | CU16 |
| CU33 | Traspasar inventario hacia donde crece la demanda | CU11 (el traspaso en sí está en CU10) |
| CU34 | Consultar pérdidas por sucursal y cambios del mes | CU25 (pérdidas); los cambios del mes van en CU16 |
| CU35 | Solicitar reporte en lenguaje natural | CU26 |
| CU36 | Exportar reporte a Excel o PDF | CU27 |
| CU37 | Consultar dashboard analítico | CU28 |
| CU38 | Entrenar o actualizar modelos de ML | CU29 |

### 6.5 Segundo parcial CU21-CU45 y numeración del diagrama 24

`24_casos_de_uso_multitenant.puml`, `ICONIX_SAAS_MULTITENANT.md` y los comentarios de
`sincronizacion/` usan la columna "Diag. 24".

| CU21-CU45 | Nombre | Diag. 24 | Diag. 10 | Ahora |
|---|---|---|---|---|
| CU21 | Registrar empresa | CU01 | — | CU01 |
| CU22 | Asignar o cambiar plan | CU02 | CU22 (parte) | CU02 |
| CU23 | Consultar estado de la suscripción | CU03 | CU21 | CU04 |
| CU24 | Renovar suscripción | CU04 | CU22, CU23 | CU05 |
| CU25 | Configurar límites del plan | CU05 | — | CU03 |
| CU26 | Gestionar clientas del tenant | CU10 | CU24 | CU08 |
| CU27 | Instalar la PWA | CU12 | CU31 (parte) | Requisito (sección 2) |
| CU28 | Descargar catálogo para uso offline | CU13 | CU31 (parte) | CU17 |
| CU29 | Consultar catálogo offline | CU14 | CU31 (parte) | CU18 |
| CU30 | Registrar reserva (online u offline) | CU15 | CU31 (parte) | CU19 |
| CU31 | Registrar venta de contado (online u offline) | CU16 | CU31 (parte) | CU20 |
| CU32 | Consultar operaciones pendientes | CU18 | — | CU21 |
| CU33 | Sincronizar operaciones pendientes | CU19 | — | CU22 |
| CU34 | Consultar resultado de la sincronización | CU20 | — | CU24 |
| CU35 | Resolver conflicto de sincronización | CU21 | — | CU23 |
| CU36 | Registrar cambio de prenda por talla | CU17 | CU25 | CU16 |
| CU37 | Imprimir nota de devolución | — | CU26 | CU16 |
| CU38 | Consultar prendas con cambio solicitado en el mes | — | CU27 | CU16 |
| CU39 | Traspasar inventario hacia donde crece la demanda | — | CU28 | CU11 |
| CU40 | Consultar pérdidas por sucursal | — | CU29 | CU25 |
| CU41 | Solicitar reporte en lenguaje natural | CU22 | CU30 | CU26 |
| CU42 | Visualizar reporte (tabla o gráfico) | CU23 | — | CU26 |
| CU43 | Exportar reporte a Excel o PDF | CU24 | — | CU27 |
| CU44 | Consultar dashboard analítico | CU26 | — | CU28 |
| CU45 | Entrenar o actualizar modelos de ML | CU27 | — | CU29 |

### 6.6 Numeración del diagrama 10 (CU21-CU31, 14/10/2026, tenant = sucursal)

La usan `10_casos_de_uso_segundo_parcial.puml`, los diagramas `11`-`19` y
`ICONIX_SEGUNDO_PARCIAL.md`. La columna "Diag. 10" de 6.5 da la equivalencia de cada número.

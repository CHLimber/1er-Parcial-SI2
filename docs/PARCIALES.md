# FashionStore: primer y segundo parcial

En este archivo se separa lo que entregó cada parcial, para documentar el segundo sin tocar el
primero. La regla es esta: **el primer parcial queda congelado**. Sus casos de uso no se
renumeran ni se reescriben. Solo se anota cuáles modifica el segundo parcial, porque ICONIX pide
analizar "los nuevos requisitos y los componentes existentes que deban modificarse" (examen 2,
4.1).

Fuentes:

- Primer parcial: `ducumentacion.docx` (CU01-CU19), `docs/uml/07_casos_de_uso.puml` y
  `movil/README.md` (CU20).
- Segundo parcial: `Examen Parcial-2 - Sistemas 2 - S2-2026.pdf`, `docs/uml/10_*.puml` y
  `24_*.puml`, `ICONIX_SEGUNDO_PARCIAL.md`, `ICONIX_SAAS_MULTITENANT.md` y el código de la rama
  `multitenant-empresa` (commit `f656ffc`, 18/10/2026).

---

## 1. Primer parcial (congelado)

### 1.1 Casos de uso numerados

| CU | Nombre | Actor principal |
|---|---|---|
| CU01 | Iniciar sesión | Todos |
| CU02 | Registrarse | Cliente |
| CU03 | Consultar catálogo | Cliente |
| CU04 | Reservar prendas | Cliente |
| CU05 | Comprar por web/app | Cliente |
| CU06 | Procesar y confirmar pago electrónico | Cliente (Stripe/QR) |
| CU07 | Registrar venta presencial | Cajero |
| CU08 | Atender reserva | Encargado |
| CU09 | Registrar recepción de mercadería | Encargado |
| CU10 | Gestionar catálogo (incluye promociones) | Administrador |
| CU11 | Gestionar proveedores | Administrador |
| CU12 | Gestionar sucursales | Administrador |
| CU13 | Gestionar usuarios y roles | Administrador |
| CU14 | Consultar historial de reservas y compras | Cliente |
| CU15 | Consultar reportes e indicadores | Encargado, Administrador |
| CU16 | Usar vestidor virtual (RA) | Cliente |
| CU17 | Recibir recomendaciones de IA | Cliente |
| CU18 | Asistir al cliente vía chatbot | Cliente |
| CU19 | Consultar bitácora de auditoría | Administrador |
| CU20 | Entrega a domicilio (libreta de direcciones y cotización del envío) | Cliente |

El docx del primer parcial llega hasta CU19. **CU20 se agregó después**, el 18/09/2026
(`PENDIENTES.txt`, 2.13), y ya está en el diagrama 07 y en la app móvil. Conviene sumarlo a la
lista del docx.

### 1.2 Casos de uso sin número (están en el diagrama 07 como include o extend)

| Caso | Relación |
|---|---|
| Cancelar reserva | extend de CU04 [PENDIENTE/CONFIRMADA/PREPARADA] |
| Informar pago QR | extend de CU06 [método = QR] |
| Verificar pago en caja (QR o efectivo) | extend de CU06 |
| Abrir o cerrar caja (arqueo) | include de CU07 |
| Confirmar o rechazar reserva | include de CU08 |
| Ajustar stock | Encargado |
| Gestionar envíos (despacho) | Encargado, Administrador |
| Consolidado de existencias | extend de CU15 |
| Reporte con IA | extend de CU15 |
| Consultar notificaciones | Todos |

La expiración de reservas y la anulación de pedidos a las 48 h las hace un temporizador
(`app/core/jobs.py`). No se modelan como actor.

---

## 2. Segundo parcial

### 2.1 Numeración (decisión)

El segundo parcial **continúa la numeración desde CU21**, porque CU01-CU20 ya son del primero.
Hasta ahora había dos numeraciones que chocaban:

- el diagrama 10 (CU21-CU31, del 14/10, con tenant = sucursal);
- el diagrama 24 (CU01-CU28, con la numeración de la especificación técnica).

Por ejemplo, "CU22" era "Pagar o cambiar el plan" en uno y "Solicitar reporte" en el otro. La
tabla de abajo es el catálogo único. Las columnas "Diag. 24" y "Diag. 10" sirven para rastrear
de dónde viene cada caso.

### 2.2 Actores

| Actor | Rol en el código | Equivale en el primer parcial a |
|---|---|---|
| Administrador de plataforma | `SUPERADMIN` (no pertenece a ninguna empresa) | No existía |
| Administrador de empresa | `ADMIN` del tenant | Administrador |
| Encargado (gerente de sucursal) | `ENCARGADO` | Encargado de sucursal |
| Empleado | `CAJERO`, `VENDEDOR` | Cajero |
| Clienta | `CLIENTE` (cuenta de la plataforma; elige la tienda con `X-Empresa`) | Cliente |
| Sistema de sincronización | temporizador o vuelta de la red | No existía |
| Claude API | servicio externo | Servicio de IA |
| Stripe | servicio externo | Sistema de pagos |

El tenant es la **empresa**, no la sucursal (decisión del 18/10/2026; ver
`ICONIX_SAAS_MULTITENANT.md`).

### 2.3 Casos de uso nuevos

Estado: **OK** = implementado y con narrativa vigente. **Actualizar** = la narrativa existe pero
asume tenant = sucursal. **Falta** = no hay narrativa.

| CU | Nombre | Actor | Diag. 24 | Diag. 10 | PDF | Código | Narrativa |
|---|---|---|---|---|---|---|---|
| **Plataforma y suscripciones** | | | | | | | |
| CU21 | Registrar empresa | Admin. plataforma | CU01 | — | 9.3 | `POST /saas/empresas` | OK |
| CU22 | Asignar o cambiar plan | Admin. plataforma | CU02 | CU22 (parte) | 9.5 | `PUT /saas/empresas/{id}/plan` | OK |
| CU23 | Consultar estado de la suscripción | Admin. plataforma, Admin. empresa | CU03 | CU21 | 9.3, 9.5 | `GET /saas/suscripcion(es)` | Actualizar |
| CU24 | Renovar suscripción (simulada: Stripe o pago manual) | Admin. empresa, Admin. plataforma | CU04 | CU22, CU23 | 9.5 | `/suscripcion/checkout`, `/suscripciones/{id}/pago-manual` | Actualizar |
| CU25 | Configurar límites del plan | Admin. plataforma | CU05 | — | 9.4 | `PUT /saas/planes/{codigo}` | OK |
| **Gestión del tenant** | | | | | | | |
| CU26 | Gestionar clientas del tenant (perfil) | Empleado, Admin. empresa | CU10 | CU24 | 9.1 | `/clientes`, `PUT /clientes/{id}/perfil` | Actualizar |
| **Operación offline y sincronización** | | | | | | | |
| CU27 | Instalar la PWA | Empleado, Clienta | CU12 | CU31 (parte) | 5.2 | `ngsw-config.json`, manifest | Falta |
| CU28 | Descargar catálogo para uso offline | Empleado | CU13 | CU31 (parte) | 6.2 | `GET /sync/catalogo` | OK |
| CU29 | Consultar catálogo offline | Empleado | CU14 | CU31 (parte) | 5.3 (1, 2) | página `offline` | OK |
| CU30 | Registrar reserva (online u offline) | Empleado | CU15 | CU31 (parte) | 5.3 (3) | `POST /sync/operaciones` | OK |
| CU31 | Registrar venta de contado (online u offline) | Empleado | CU16 | CU31 (parte) | 5.3 (4), 7.2 | `POST /sync/operaciones` | OK |
| CU32 | Consultar operaciones pendientes | Empleado | CU18 | — | 5.3 (5) | `GET /sync/operaciones` | OK |
| CU33 | Sincronizar operaciones pendientes | Empleado, Sistema de sincronización | CU19 | — | 5.4, 6.4 | `POST /sync/operaciones` | OK |
| CU34 | Consultar resultado de la sincronización | Empleado, Encargado | CU20 | — | 6.2 | `/panel/sincronizacion` | OK |
| CU35 | Resolver conflicto de sincronización | Empleado, Encargado, Admin. empresa | CU21 | — | Obj. esp. 9 | `POST /sync/operaciones/{id}/resolver` | OK |
| **Cambios de prenda** | | | | | | | |
| CU36 | Registrar cambio de prenda por talla | Empleado, Encargado | CU17 | CU25 | 7.2 | `POST /devoluciones/{id}/cambio` | OK |
| CU37 | Imprimir nota de devolución | Encargado | — | CU26 | 7.2 (aporte) | `GET /devoluciones/{id}/nota` | OK |
| CU38 | Consultar prendas con cambio solicitado en el mes | Encargado | — | CU27 | 7.2 (aporte) | `GET /devoluciones/cambios-mes` | OK |
| **Inventario y pérdidas** | | | | | | | |
| CU39 | Traspasar inventario hacia donde crece la demanda | Encargado | — | CU28 | 7.2 (aporte) | `/traspasos`, `/sugerencias` | Actualizar |
| CU40 | Consultar pérdidas por sucursal | Encargado, Admin. empresa | — | CU29 | 7.2 (aporte) | `GET /reportes/perdidas` | OK |
| **Reportes con IA** | | | | | | | |
| CU41 | Solicitar reporte en lenguaje natural (texto o voz) | Encargado, Admin. empresa | CU22 | CU30 | 8.1, 8.3 | `POST /reportes/consulta-ia`, `shared/voz.ts` | OK |
| CU42 | Visualizar reporte (tabla o gráfico) | Encargado, Admin. empresa | CU23 | — | 8.3 | página `reportes` | Falta |
| CU43 | Exportar reporte a Excel o PDF | Encargado, Admin. empresa | CU24 | — | 8.1, 8.5 | página `reportes` | Falta |
| **Analítica con machine learning** | | | | | | | |
| CU44 | Consultar dashboard analítico | Encargado, Admin. empresa | CU26 | — | 8.4, 8.5 | `GET /analitica/dashboard` | OK |
| CU45 | Entrenar o actualizar modelos de ML | Admin. plataforma | CU27 | — | 8.4, 8.5 | `POST /analitica/entrenar` | OK |

Los casos sin número que hay que dibujar como include o extend son estos:

- Verificar límite del plan: include de CU12, CU13 y CU22.
- Validar plan Profesional: include de CU41 y CU44.
- Asignar identificador único y estado local: include de CU30 y CU31.
- Validar tenant y suscripción: include de CU33.
- Verificar idempotencia: include de CU33.
- Resolver conflicto: extend de CU33, con la condición [conflicto o rechazo]. Es el CU35.
- Manejar solicitud ambigua o no soportada: extend de CU41.
- Dictar la solicitud por voz: extend de CU41. Está implementado, pero **no figura en ningún
  diagrama**.
- Imprimir nota: extend de CU36. Es el CU37.

### 2.4 Casos de uso del primer parcial que modifica el segundo

No se renumeran. Solo se documenta el cambio.

| CU | Qué cambia | Diag. 24 | PDF |
|---|---|---|---|
| CU01 Iniciar sesión | El token lleva la empresa. El backend la toma del token, nunca de un parámetro. | CU11 | 9.6, RNF01 |
| CU03 a CU06 (compra y RA) | La clienta elige la tienda con `X-Empresa`; el carrito no mezcla prendas de dos empresas. | CU28 | 9.6, 11 |
| CU04 Reservar prendas | La reserva online de la clienta sigue igual. La del personal pasa a CU30, que también funciona offline. | CU15 | 5.3 |
| CU07 Registrar venta presencial | Tiene una variante offline, que es CU31. | CU16 | 7 |
| CU09 Registrar recepción, más "Ajustar stock" | Pasa a "Gestionar inventario", aislado por empresa. | CU09 | 9.1 |
| CU10 Gestionar catálogo | El catálogo es de cada empresa. | CU08 | 9.1 |
| CU12 Gestionar sucursales | Respeta el tope de sucursales activas del plan (2 o 10). | CU06 | 9.4 |
| CU13 Gestionar usuarios y roles | Los roles y usuarios son de cada empresa. | CU07 | 9.3 |
| CU15 Consultar reportes e indicadores | Son los "reportes convencionales" del plan, filtrados por empresa. | CU25 | 9.4 |

Los demás (CU02, CU08, CU11, CU14, CU16 a CU20) siguen como estaban. Solo heredan el filtro por
empresa del backend.

---

## 3. Qué falta en la documentación del segundo parcial

Sigue el índice del examen (capítulos II y III).

1. **2.5 Diagrama de casos de uso.** Rehacer un solo diagrama con CU21-CU45 y los casos del
   punto 2.4 marcados como modificados. Los diagramas 10 y 24 quedan como historia.
2. **2.6 Especificaciones.** Escribir las que dicen "Falta" (CU27, CU42, CU43). Actualizar a
   tenant = empresa las que dicen "Actualizar" (CU23, CU24, CU26, CU39). Renumerar las narrativas
   de `ICONIX_SAAS_MULTITENANT.md` (están con la numeración de la especificación).
3. **Corregir el diagrama 10.** Tiene `Admin --|> Encargado`, y eso contradice que el SUPERADMIN
   no pertenece a ninguna empresa.
4. **Decidir si CU36 (cambio de prenda) funciona offline.** El diagrama 24 lo pone en el paquete
   offline, pero las operaciones offline solo son venta y reserva. El PDF (7.2) no lo aclara. O se
   saca del paquete o se implementa offline, y la decisión se anota.
5. **3.1 a 3.5.** Ya existen el modelo de dominio (`23`), las robusteces (`11`-`16`, `25`, `28`),
   las secuencias (`17`, `18`, `26`) y el modelo SQLite (`27`). Hay que revisar que usen la
   numeración nueva. El diagrama de clases de diseño (`19`) es del 14/10, con tenant = sucursal:
   hay que revisarlo.
6. **3.6 Interfaces.** No hay un documento propio todavía.

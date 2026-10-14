# Diagramas UML de FashionStore

Modelos UML 2.5 en PlantUML para los flujos de trabajo del PUDS (Análisis y Diseño). Se
armaron **leyendo el código real** del 24/09/2026 (`fashionstore/db/01_schema.sql`,
`db/02_logica.sql`, `backend/app/modules/reservas|pagos|caja|ventas`, `app/core/jobs.py`,
`app/core/mutex.py` y la app Flutter), no la documentación, así que los nombres de estados,
endpoints y mensajes coinciden con lo que hace el sistema.

Cada `.puml` es un diagrama; su PNG ya renderizado está en `png/`.

| Archivo | Tipo UML | Qué muestra |
|---|---|---|
| `01_estados_reserva.puml` | Máquina de estados | Ciclo de vida de la reserva de vestidor (`estado_reserva`) |
| `02_estados_item_reserva.puml` | Máquina de estados | Cada prenda de la reserva (`reserva_detalle.estado_item`) |
| `03_estados_unidad_stock.puml` | Máquina de estados | Una unidad de stock por sucursal y los movimientos del kardex |
| `04_estados_venta_pago.puml` | Máquina de estados | Venta (`estado_venta`) y pago (`estado_pago`) por método: Stripe, QR y efectivo |
| `05_secuencia_reserva_concurrente.puml` | Secuencia | Dos clientas reservan a la vez la última unidad |
| `06_secuencia_compra_movil.puml` | Secuencia | Compra desde la app móvil con Stripe, y la variante QR |
| `07_casos_de_uso.puml` | Casos de uso | Actores finales y casos de uso del sistema |
| `08_clases_dominio.puml` | Clases | Modelo de dominio de inventario, reservas, ventas y pagos |
| `09_modelo_dominio_segundo_parcial.puml` | Clases (ICONIX dominio) | Segundo parcial: SaaS, cambio por talla, traspasos por demanda |
| `10_casos_de_uso_segundo_parcial.puml` | Casos de uso | CU21-CU31 del Segundo parcial |
| `11`-`16_robustez_*.puml` | Robustez / comunicación | Un diagrama por CU clave (mensajes numerados) |
| `17_secuencia_cambio_talla.puml`, `18_secuencia_pago_suscripcion.puml` | Secuencia | Diseño de CU25 y CU22 |
| `19_clases_diseno.puml` | Clases de diseño | Backend, web y móvil del Segundo parcial |
| `20`-`22_c4_*.puml` | C4 | Contexto, contenedores y componentes de la API |

Narrativas de casos de uso y explicacion ICONIX/C4: `ICONIX_SEGUNDO_PARCIAL.md`.

## 1. Estados de la reserva

Las transiciones siguen la notación `evento [guarda] / efecto`, y `«Actor»` indica quién las
dispara. La reserva **nace PENDIENTE** (`POST /reservas`) y compromete stock desde ese momento:
el trigger `tg_reserva_compromete_stock` registra un movimiento RESERVA por cada prenda. Después:

- El **Encargado** la confirma (`/confirmar` → CONFIRMADA) o la rechaza con un motivo
  (`/rechazar` → CANCELADA, con LIBERACION).
- Prepara las prendas (`/preparar` → PREPARADA). Si ninguna estaba disponible, la reserva pasa
  a CANCELADA.
- Marca que la clienta llegó (`/presente` → CLIENTE_PRESENTE) y registra la decisión
  (`/resolver`). ATENDIDA es un estado transitorio dentro de esa misma transacción. Si la clienta
  compró algo, la reserva queda CONVERTIDA; si no compró nada, queda CANCELADA.
- La **clienta** puede cancelar mientras la reserva está en PENDIENTE, CONFIRMADA o PREPARADA,
  siempre que siga vigente y no tenga un pago en curso.
- El **job** `fn_expirar_reservas` (con `FOR UPDATE SKIP LOCKED`) la vence a EXPIRADA cuando
  pasa `expira_en`, salvo que haya una venta PENDIENTE ligada. `expira_en` se cuenta desde la
  hora de la visita. El Encargado también puede expirarla a mano con `/no-presentado`.
- Si la clienta compra en línea lo que reservó (un carrito armado desde la reserva),
  `confirmar_aprobado` la deja CONVERTIDA.

## 2. Estados de cada prenda de la reserva

- **RESERVADO** → **PREPARADO** cuando el Encargado la prepara, o → **DESCARTADO** si ya no
  está en tienda.
- **PREPARADO** → **COMPRADO** o **DESCARTADO** según lo que se decida en `/resolver`.
- Cualquier prenda que siga comprometiendo stock pasa a **DESCARTADO** si la reserva se cancela
  o expira.

Cada paso a DESCARTADO libera el stock en la misma transacción, lo que evita una doble
liberación. **PROBADO** existe en el ENUM, pero ningún código lo asigna (aparece en gris).

## 3. Estados de la unidad de stock

Modela una unidad de *cantidad* de una variante (talla × color) en una sucursal. El stock no se
lleva por número de serie. Los estados y movimientos son:

- PRÓXIMA A INGRESAR (en una recepción BORRADOR) pasa a DISPONIBLE con **ENTRADA**, al confirmar
  la recepción.
- DISPONIBLE ↔ RESERVADA con **RESERVA** y **LIBERACION**.
- La unidad pasa a VENDIDA con **SALIDA**, o con **LIBERACION + SALIDA** si venía de una reserva.
- **AJUSTE** fija `cantidad_fisica` en el valor contado.

El invariante es `cantidad_fisica >= cantidad_reservada >= 0` (CHECK `ck_inventario_saldos`).
DEVOLUCION y los traspasos están en el ENUM, pero no hay un flujo que los use.

## 4. Estados de la venta y del pago

La región **Venta** tiene tres caminos:

- Una venta online nace PENDIENTE. Pasa a PAGADA cuando se aprueba el pago, y después a
  ENTREGADA cuando el envío llega a domicilio.
- Si el pago termina RECHAZADO o REEMBOLSADO, la venta queda ANULADA.
- Una venta POS nace ya PAGADA.

En la región **Pago**, el estado PENDIENTE se divide por método:

- **STRIPE**: lo resuelve el webhook firmado (`payment_intent.succeeded`,
  `checkout.session.completed`, `…canceled/failed/expired`).
- **QR**: la clienta *informa* el pago (`informado_en`) y el **Cajero** lo aprueba o rechaza
  desde caja.
- **EFECTIVO**: lo aprueba o rechaza el Cajero, y para aprobarlo necesita una sesión de caja
  abierta.

Los pedidos EFECTIVO o QR que nadie informó se rechazan a las 48 h (`app/core/jobs.py`). Al
aprobar, un punto de decisión revisa si el stock o el carrito cambiaron. Si cambiaron y la plata
ya se había cobrado (STRIPE o QR), el pago queda REEMBOLSADO. Si era EFECTIVO, queda RECHAZADO.

## 5. Secuencia: reserva concurrente de la última unidad

Dos clientas piden la misma unidad. El mutex de aplicación (`app/core/mutex.py`) es una capa
opcional que solo funciona dentro de un mismo proceso. Con el mutex, la segunda clienta ve
`disponible = 0` en el pre-chequeo y recibe *"Stock insuficiente"*.

La garantía real es el `FOR UPDATE` de `fn_mover_inventario`. Sin mutex (varios workers o
instancias), la segunda transacción espera el COMMIT de la primera, lee el saldo actualizado y
recibe un error. El backend lo convierte en *"Otro cliente reservo esa unidad justo antes"*.

## 6. Secuencia: compra desde la app móvil

**Stripe:**

1. La app llama a `POST /ventas/checkout` con `canal: MOVIL` y recibe el `client_secret` del
   PaymentIntent.
2. La clienta paga en el PaymentSheet nativo.
3. Stripe llama a `POST /pagos/webhook/stripe` y el backend valida la firma. La idempotencia se
   asegura con `evento_pasarela`.
4. `confirmar_aprobado` registra `venta_detalle` (y con eso la SALIDA de stock), el comprobante
   y la notificación *"Pago aprobado"*.
5. La campana de la app consulta `/notificaciones/no-leidas/cantidad` cada 60 s.

**Variante QR:** la clienta informa el pago (`/pagos/qr/{id}/informar`). Los cajeros reciben un
aviso, y el Cajero verifica el depósito y lo aprueba o rechaza desde `/caja/pagos/{id}/...`.

## 7. Casos de uso

**Actores humanos:**

- **Cliente.**
- **Cajero.**
- **Encargado de sucursal.** Hereda del Cajero porque tiene los permisos `caja.crear` y
  `ventas.crear`, y absorbe las tareas del antiguo rol Almacén.
- **Administrador.**

**Actores secundarios:** Sistema de pagos (Stripe/QR), Servicio de IA (Claude API), Servicio de
delivery externo y Servicio de ruteo (openrouteservice).

Además de CU01–CU20, el diagrama incluye cancelar reserva, confirmar/rechazar reserva, informar
pago QR, verificar pago en caja, consultar notificaciones y el consolidado de existencias
(`v_existencias_consolidadas`, que extiende CU15). Las tareas automáticas (expiración y
anulación a las 48 h) no se modelan como actor: están en una nota.

## 8. Clases de dominio

Es una versión simplificada de `01_schema.sql`. El stock vive en `Inventario`, que asocia
`Sucursal` y `ProductoVariante`, nunca en `Producto`. `MovimientoInventario` y
`ReservaHistorial` son append-only. `Venta` une los tres canales y puede ligarse a una `Reserva`
y a un `Carrito`. `Pago` usa `EventoPasarela` para la idempotencia. Los ENUM de estado aparecen
como enumeraciones.

## Cómo renderizar

Se necesita Java 8 o superior y `plantuml.jar` (https://plantuml.com/download). Graphviz no hace
falta: los diagramas de estados, casos de uso y clases declaran `!pragma layout smetana`, que es
el motor de layout propio de PlantUML. Si tenés Graphviz instalado y preferís su layout, borrá
esa línea.

```bash
# desde fashionstore/docs/uml/
java -jar plantuml.jar -charset UTF-8 -tpng -o png *.puml    # PNG en png/
java -jar plantuml.jar -charset UTF-8 -tsvg -o svg *.puml    # SVG (escala sin perder calidad)
```

Alternativas: la extensión *PlantUML* de VS Code (Alt+D para la vista previa), o pegar el
contenido en https://www.plantuml.com/plantuml. Los PNG de `png/` se generaron con PlantUML
1.2023.13 y Java 1.8.

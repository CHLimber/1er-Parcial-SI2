# Segundo parcial — Análisis y diseño con ICONIX (UML 2.5.1) y arquitectura C4

Tema: **pérdida**. Este documento recorre las cuatro etapas de ICONIX para lo que suma el
segundo parcial: PWA offline/online, SaaS multi-tenant con tres planes, cambio de prenda por
talla, traspasos hacia donde crece la demanda, reportes con IA de varias sucursales y el reporte
de pérdidas. Todos los diagramas están en esta carpeta (fuente PlantUML) y en `png/` (imagen).
Se escribieron leyendo el código real del 14/10/2026, así que los nombres coinciden con el
sistema.

| Etapa ICONIX | Artefacto | Archivo |
|---|---|---|
| Análisis de requisitos | Modelo de dominio | `09_modelo_dominio_segundo_parcial.puml` |
| Análisis de requisitos | Modelo de casos de uso + narrativas | `10_casos_de_uso_segundo_parcial.puml` y sección 2 |
| Análisis y diseño preliminar | Diagramas de robustez (= comunicación) | `11` a `16` |
| Diseño | Diagramas de secuencia | `17_secuencia_cambio_talla.puml`, `18_secuencia_pago_suscripcion.puml` |
| Diseño | Diagrama de clases de diseño | `19_clases_diseno.puml` |
| Arquitectura | C4 contexto, contenedores, componentes | `20`, `21`, `22` |

Para regenerar los PNG (sin instalar nada, con Docker):

```bash
cd fashionstore/docs/uml
docker run --rm -v "$PWD:/data" -w /data plantuml/plantuml -tpng -o png -charset UTF-8 *.puml
```

## 1. Modelo de dominio

Clases nuevas (en rosa en el diagrama): `Plan`, `Suscripcion`, `PagoSuscripcion`,
`ClientePerfilTenant` y `SugerenciaTraspaso` (calculada, no se guarda). `Devolucion` gana el
número de nota, el motivo estructurado y las condiciones; `DevolucionDetalle` gana la variante
solicitada a cambio; `Configuracion` gana `cambio_plazo_dias`.

> **Superado el 18/10/2026:** la especificación técnica del SaaS dice que una sucursal *no* es un
> tenant. Ahora el tenant es la **empresa**: ver `ICONIX_SAAS_MULTITENANT.md` y el diagrama `23`.
> El párrafo siguiente queda como historia de la decisión.

Decisión de diseño (primera versión): **tenant = sucursal**, tal como lo pide la consigna. Cada sucursal tiene su
suscripción y su cartera de clientas. El catálogo es de la cadena, porque lo provee la casa
matriz; así los traspasos y los reportes de varias sucursales siguen funcionando.

## 2. Casos de uso (narrativas)

Formato ICONIX: curso básico en voz activa y cursos alternos, con los nombres de los objetos del
dominio.

### CU21 Consultar plan y suscripción del tenant

- **Actor:** Encargado (administración del tenant); el Administrador ve todos los tenants.
- **Curso básico:** el Encargado abre «Suscripción». El sistema muestra el `Plan` de su
  `Sucursal`, el estado de la `Suscripcion`, la fecha de vencimiento, los días restantes, el uso
  de personal y cajas frente a los topes del plan, los tres planes disponibles y el historial de
  `PagoSuscripcion`.
- **Alterno A1:** la suscripción venció. El sistema la muestra como «Vencida» y avisa que el
  perfil de clientas, los traspasos y la IA quedan bloqueados.
- **Alterno A2:** el actor es el Administrador. El sistema lista todos los tenants y le deja
  elegir uno.

### CU22 Pagar o cambiar el plan de la suscripción

- **Actor:** Encargado. Sistema externo: Stripe.
- **Curso básico:** el Encargado elige un plan y la cantidad de meses (1, 3, 6 o 12). El sistema
  crea un `PagoSuscripcion` PENDIENTE por precio × meses, abre un Checkout de Stripe en bolivianos
  y redirige. La clienta del SaaS (el Encargado) paga. Stripe avisa por webhook (o el sistema lo
  consulta al volver) y el sistema aprueba el pago. Después extiende `vence_en` desde el fin del
  período vigente, deja el plan pagado como plan del tenant, marca la suscripción ACTIVA y
  notifica.
- **Alterno A1:** la suscripción ya había vencido. El nuevo período arranca hoy.
- **Alterno A2:** el Encargado cancela en Stripe. El sistema muestra que la suscripción sigue
  como estaba.
- **Alterno A3:** llegan el webhook y la verificación. El segundo no hace nada, porque el pago
  ya no está PENDIENTE (idempotencia).

### CU23 Registrar pago manual de una suscripción

- **Actor:** Administrador de la plataforma.
- **Curso básico:** el Administrador elige el tenant, el plan, los meses y el medio
  (transferencia o efectivo). El sistema crea el pago ya APROBADO, extiende la suscripción y deja
  registro en la bitácora.
- **Alterno A1:** un Encargado intenta registrarlo. El sistema responde 403.

### CU24 Gestionar el perfil de las clientas del tenant

- **Actor:** Encargado; el Vendedor solo consulta.
- **Precondición:** el plan incluye «perfil de clientas» y la suscripción está vigente.
- **Curso básico:** el Encargado abre «Clientas». El sistema arma la cartera de su sucursal: las
  clientas que compraron o reservaron ahí y las que se agregaron a mano. Para cada una muestra
  compras, total, última compra, reservas y segmento: el fijado en la ficha o, si no hay uno, el
  sugerido por el historial (NUEVA, FRECUENTE, VIP o INACTIVA). El Encargado elige una clienta y
  edita talla habitual, estilo, teléfono, WhatsApp, notas y segmento. El sistema guarda el
  `ClientePerfilTenant` de esa sucursal y lo audita.
- **Alterno A1:** agregar por email. Si no existe una cuenta CLIENTE con ese email, el sistema
  responde 404.
- **Alterno A2:** el plan es Básico. El sistema responde 403 e indica desde qué plan está
  incluido. Si la suscripción venció, responde 402.

### CU25 Registrar cambio de prenda por talla

- **Actor:** Encargado o Cajero.
- **Curso básico:** el Encargado busca la `Venta` por número y elige el motivo «Cambio por
  talla». El sistema muestra hasta cuándo se puede cambiar (`cambio_plazo_dias`, 15 días) y, para
  cada prenda, las otras tallas del mismo color con su disponible en la sucursal. El Encargado
  verifica y marca las condiciones (comprobante, etiqueta, sin uso), indica unidades y la talla
  que se lleva la clienta. El sistema valida las condiciones, que la variante sea la misma prenda
  en otra talla y que haya stock. Después registra la `Devolucion` SOLICITADA con número de nota
  NDV-xxxxxx.
- **Alterno A1:** venció el plazo de cambio. El sistema no deja registrar (409).
- **Alterno A2:** falta una condición. El sistema responde 409 «falta la etiqueta original…».
- **Alterno A3:** no hay stock de la talla pedida. El sistema responde 409 y sugiere pedirla
  por traspaso.
- **Alterno A4:** el motivo es DEFECTO. El sistema solo exige el comprobante y aplica el plazo
  de devolución (30 días).
- **Continuación:** al aprobarla, el trigger reingresa el stock. La prenda nueva se cobra en caja
  y se vincula como venta del cambio.

### CU26 Imprimir nota de devolución (extiende CU25)

- **Curso básico:** desde la devolución, el Encargado pide «Imprimir nota». El sistema arma el
  comprobante con razón social, NIT, sucursal, número NDV, venta, clienta, motivo, condiciones
  verificadas, plazo aplicado, prendas devueltas y lo que se lleva a cambio, monto y firmas, y
  abre la impresión (o «Guardar como PDF»).

### CU27 Consultar prendas con cambio solicitado en el mes

- **Actor:** Encargado (su sucursal) o Administrador (toda la cadena).
- **Curso básico:** el Encargado abre «Cambios del mes» y elige el mes. El sistema agrupa las
  devoluciones con motivo TALLA o COLOR por prenda, talla y color devueltos frente a lo pedido a
  cambio. Muestra solicitudes, unidades, cuántas se aprobaron, rechazaron o siguen pendientes, y
  en qué sucursales.
- **Alterno A1:** «incluir otros motivos» suma también defectos, «no le gustó», etc.

### CU28 Traspasar inventario hacia donde crece la demanda

- **Actor:** Encargado del origen o Administrador.
- **Precondición:** el plan incluye «traspasos» y está vigente.
- **Curso básico:** el Encargado abre «Sugerencias por demanda» y elige la ventana (7, 14 o 30
  días) y el horizonte a cubrir. Para cada prenda y sucursal, el sistema compara lo vendido en la
  ventana reciente con la anterior. Si la demanda crece y el disponible no alcanza para el
  horizonte, busca la sucursal a la que más le sobra (por encima de su stock mínimo y de su
  propia demanda) y propone mover lo que falta. Muestra las sugerencias agrupadas por origen y
  destino. El Encargado elige «Crear traspaso» y el sistema crea el `Traspaso` SOLICITADO. El
  resto sigue el flujo de siempre: despachar y recibir, con los triggers moviendo el stock.
- **Alterno A1:** ya hay un traspaso abierto con esa prenda hacia ese destino. El sistema no la
  vuelve a sugerir.
- **Alterno A2:** un Encargado intenta crear desde una sucursal que no es la suya. El sistema
  responde 403.

### CU29 Consultar pérdidas por sucursal (tema del parcial)

- **Actor:** Encargado o Administrador.
- **Curso básico:** el Encargado elige «Pérdidas por sucursal» y el período. El sistema calcula
  para cada sucursal:
  - las mermas: ajustes de inventario a la baja, valorizados;
  - las devoluciones aprobadas por defecto: unidades y monto reintegrado;
  - los faltantes de traspaso: lo despachado que no llegó;
  - los faltantes de caja.

  Muestra el total ordenado de mayor a menor y permite exportarlo a PDF o Excel.

### CU30 Consultar reportes con IA de varias sucursales

- **Actor:** Encargado o Administrador. Sistema externo: Claude API.
- **Precondición:** plan Premium vigente (el Administrador siempre puede).
- **Curso básico:** el Administrador escribe o dicta una pregunta, por ejemplo «compará las
  ventas y las pérdidas de las seis sucursales este mes». El sistema le pasa a Claude las
  herramientas de reportes. Claude pide la consulta que corresponde (ventas por sucursal,
  pérdidas, existencias, top productos…); el sistema la ejecuta contra la base y le devuelve la
  tabla. Claude responde en texto y el sistema muestra la respuesta con la tabla.
- **Alterno A1:** plan sin IA. El sistema responde 403 «incluido desde el plan Premium».
- **Alterno A2:** falta `ANTHROPIC_API_KEY`. El sistema responde 503.

### CU31 Usar la tienda sin conexión (PWA web y app móvil)

- **Actor:** Clienta.
- **Curso básico:** la Clienta abre la tienda sin red. El service worker sirve la app y el
  interceptor de la web (o el `ApiClient` en el móvil) intenta la red. Al fallar, responde con la
  última copia guardada en la base temporal: IndexedDB en la web, SQLite en el móvil. El aviso
  dice «Sin conexión · datos del dd/mm hh:mm».
- **Alterno A1:** la Clienta toca «Comprar ahora» sin red. El sistema guarda la operación en la
  cola local y avisa que se agrega sola. Al volver la red, sincroniza en orden y avisa cuántas
  operaciones se enviaron. Si el backend rechaza alguna (por ejemplo, sin stock), la descarta y
  lo informa.
- **Alterno A2:** acciones que necesitan red de verdad (pagar, reservar, gestión). El sistema
  muestra «Sin conexión: esta acción necesita internet».
- **Postcondición:** al cerrar sesión se vacía la base temporal.

## 3. Robustez (= comunicación)

Cada diagrama (`11` a `16`) respeta las reglas de ICONIX:

- el actor solo habla con objetos *boundary*;
- los *boundary* hablan con *control*;
- los *control* hablan con *entity* y con otros *control*.

Los mensajes están numerados, así el mismo diagrama se lee como diagrama de comunicación UML
2.5.1, que es lo que pide la consigna («robustez = comunicación»).

| Diagrama | Caso de uso |
|---|---|
| 11 | CU25 cambio por talla (+ CU26 nota) |
| 12 | CU22 pago de suscripción con Stripe |
| 13 | CU28 traspaso por demanda |
| 14 | CU31 offline (PWA y móvil) |
| 15 | CU30 IA de varias sucursales (+ CU29 pérdidas como herramienta) |
| 16 | CU24 perfil de clientas del tenant |

## 4. Diseño: secuencia y clases

- `17_secuencia_cambio_talla`: los controles del diagrama 11 convertidos en llamadas reales
  (`buscarVenta`, `variantesCambio`, `POST /devoluciones` con `condiciones_faltantes` y
  `_validar_cambio_linea`, `nota`).
- `18_secuencia_pago_suscripcion`: Checkout, el webhook y la verificación corriendo en paralelo,
  y la idempotencia de `aplicar_pago`.
- `19_clases_diseno`: módulos del backend (`app.core.plan`, `saas`, `clientes`, `devoluciones`,
  `traspasos`, `reportes`, `pagos`), servicios y páginas de Angular, la capa offline web
  (`offlineInterceptor`, `ConexionService`, `offlineDb`) y la del móvil (`ApiClient`,
  `ConexionService`, `BaseLocal`).

## 5. Arquitectura C4

- **Nivel 1, contexto (`20`):** clienta, personal, administrador de la plataforma, y los
  sistemas externos Stripe, Claude, openrouteservice, el delivery externo y los mapas.
- **Nivel 2, contenedores (`21`):** la PWA Angular con su IndexedDB, la app Flutter con su
  SQLite, Nginx, la API FastAPI y PostgreSQL.
- **Nivel 3, componentes de la API (`22`):** autorización por permiso, control de plan del
  tenant, SaaS, cartera de clientas, devoluciones y cambios, traspasos, reportes con IA, pagos y
  auditoría.

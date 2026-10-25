# Documento SQL del informe (Capítulo 8 – Diseño de datos)

`docs/FASHIONSTORE_BD.sql` es el SQL que va en el informe: 8.2.2 Script, 8.2.4 Población,
8.2.5 Consultas y 8.2.6 Procedimientos, funciones y triggers. **No se edita a mano**: se arma con
`armar.py` a partir de dos fuentes.

| Sección del documento | Fuente | Qué hacer cuando cambia |
|---|---|---|
| 8.2.2 Script (extensiones, ENUM, tablas, índices) | `db/01_schema.sql`, completo desde `EXTENSIONES` | Nada: `armar.py` lo copia. El número de tablas de la cabecera se recalcula solo |
| 8.2.2 Vistas, 8.2.6.2 Funciones, 8.2.6.3 Triggers | `db/02_logica.sql`, por secciones | Nada si se modifica una sección existente. Si se **agrega** una sección nueva, `armar.py` falla hasta que se la clasifique en `VISTAS`, `FUNCIONES` o `TRIGGERS` (listas al inicio del script) |
| Cabecera e índice del archivo | `00_cabecera.sql` | Editar a mano |
| Encabezado de las vistas | `10_vistas_cabecera.sql` | Editar a mano |
| 8.2.4 Población (Insert, Update, Delete), 8.2.5 Consultas, 8.2.6.1 Procedimientos | `20_poblacion_a_procedimientos.sql` | Editar a mano (ver abajo) |
| Encabezado de 8.2.6.3 | `60_triggers_cabecera.sql` | Editar a mano |
| 8.2.6.4 Pruebas | `70_pruebas.sql` | Editar a mano: agregar una prueba por cada trigger, función o procedimiento nuevo |

## Rearmar y probar

Desde `fashionstore/`, con el Postgres de Docker levantado:

```bash
python docs/bd_documento/armar.py
docker exec fashionstore-db-1 psql -U fashionstore -d fashionstore -c "CREATE DATABASE fs_documento_prueba;"
docker exec -i fashionstore-db-1 psql -U fashionstore -d fs_documento_prueba -v ON_ERROR_STOP=1 < docs/FASHIONSTORE_BD.sql
docker exec fashionstore-db-1 psql -U fashionstore -d fashionstore -c "DROP DATABASE fs_documento_prueba;"
```

Tiene que terminar sin `ERROR`. Los `NOTICE: Rechazado: ...` son esperados: son las pruebas de los
casos de error.

## Qué revisar a mano cuando cambia el esquema

- **Columna nueva NOT NULL sin DEFAULT, o CHECK nuevo:** los `INSERT` de la población pueden
  fallar. Agregar el valor en `20_poblacion_a_procedimientos.sql`.
- **Tabla nueva:** agregarle al menos un `INSERT` de ejemplo y, si es importante, una consulta.
- **Tabla o columna renombrada:** buscarla en los archivos de esta carpeta (población, consultas,
  procedimientos y pruebas la nombran a mano).
- **Cambio en la fórmula de la venta** (IVA sobre `subtotal - descuento`; total = base + IVA +
  envío, en `ventas/router.py`): recalcular los montos fijos de las ventas de ejemplo, de las
  sesiones de caja cerradas (`monto_sistema` = inicial + efectivo) y del arqueo de la prueba.
- **Lógica de backend replicada en un procedimiento:** `sp_venta_pos` replica `POST /ventas/pos`,
  `sp_cerrar_sesion_caja` replica `POST /caja/cerrar` y `sp_renovar_suscripcion` replica la
  renovación de `/saas`. Si cambia el endpoint, actualizar el procedimiento.

## Datos fijos que usan las pruebas

Los UUID de la población son fijos para poder nombrarlos en Update/Delete y en las pruebas:
empresas `e0000000-…-00000000000{1,2,3}`, ventas `b1…`, detalle de venta `b3…`, pagos `b2…`,
reservas `c1…`, sesiones de caja `d1…`, recepción `f1…`, traspaso `f2…`, devolución `f3…`,
carrito `f4…`, envío `f5…`, operación offline `a1…`. El stock inicial es fijo (no `random()`)
para que las consultas den siempre lo mismo en el informe.

# FashionStore

Plataforma de comercio electronico e inteligencia de tienda para una cadena de **moda femenina**
con sucursales en Bolivia. Proyecto de Sistemas II (S2-2026).

## Modelo de negocio

**Publico objetivo:** mujeres de 18 a 40 anios en Santa Cruz, La Paz y Cochabamba. Todo el
catalogo es genero `MUJER`; el resto del ENUM `genero_prenda` queda disponible como capacidad de
crecimiento, pero fuera del alcance actual.

**Por que mujer y no un catalogo general.** El tallaje femenino es inconsistente entre marcas y
cortes: una M de una marca no es una M de otra. Por eso la clienta necesita probarse antes de
comprar, y por eso la reserva de vestidor (CU04, atendida en CU08) es el corazon del producto y no
un agregado. En ropa masculina la talla es estable y la compra es directa, asi que ese flujo
perderia sentido. Ademas, el surtido femenino de talla x color es amplio, que es lo que justifica
modelar `producto_variante` como la unidad fisica real en vez de guardar el stock en `producto`.

**Las tres sucursales estan en tres climas distintos**, y eso manda sobre el inventario:

| Sucursal              | Ciudad      | Clima                    | Surtido que pesa   |
|-----------------------|-------------|--------------------------|--------------------|
| FashionStore Equipetrol | Santa Cruz  | Llanura, calido todo el anio | Primavera-Verano |
| FashionStore Sopocachi  | La Paz      | Altura, frio todo el anio    | Otonio-Invierno  |
| FashionStore Cala Cala  | Cochabamba  | Valle templado               | Equilibrado      |

La misma coleccion no se reparte en partes iguales entre las tres tiendas: un tapado de lana rota
en Sopocachi y se queda parado en Equipetrol. Esa es la razon de negocio por la que el stock vive
por sucursal (`inventario`, una fila por sucursal x variante) y no como un unico saldo global, y
por la que existen los traspasos entre tiendas (panel **Traspasos**: el encargado del origen
despacha y el stock sale de su tienda; el del destino cuenta lo que llego y eso entra en la suya).
El seed refleja esa asimetria, no carga cantidades uniformes.

**Temporadas.** Cada prenda puede pertenecer a una temporada (`temporada` / `coleccion`) o ser
atemporal. El seed deja el ciclo completo a la vista: Otonio-Invierno 2026 ya cerrada, con su
liquidacion corriendo (`INVIERNO30`), y Primavera-Verano 2026 activa (`VERANO15`). El jean no
lleva temporada: rota parejo todo el anio en las tres ciudades.

**Ingresos:** venta directa con margen sobre prenda importada y de proveedor nacional, por dos
canales ya implementados — compra online con pago por pasarela y retiro en sucursal (CU05/CU06), o
reserva de vestidor gratuita y pago presencial en caja (CU04/CU07).

## Estructura

```
fashionstore/
├── backend/     # FastAPI + asyncpg (Python 3.12)
├── frontend/    # Angular 20 standalone
├── movil/       # Flutter (por implementar)
├── db/          # Esquema, logica y datos iniciales de Postgres
└── docker-compose.yml
```

### Puertos

Para evitar choques con otros servicios que puedan estar ocupando los puertos por defecto, este
proyecto usa puertos no estandar en el host:

| Servicio           | URL local                 |
|---------------------|----------------------------|
| Frontend (Angular)  | http://localhost:3000      |
| Backend (FastAPI)   | http://localhost:8081      |
| Postgres            | localhost:5433              |

(Adentro de la red de Docker, `backend` sigue hablando con `db` por el puerto interno `5432`; solo
cambia el puerto publicado al host.)

## Levantar el entorno local

Requiere Docker y Docker Compose.

```bash
docker compose up --build
```

Esto levanta:

- **db**: Postgres 16 en `localhost:5433` (usuario/clave/base: `fashionstore`). En el primer
  arranque ejecuta automaticamente, en orden, `db/01_schema.sql`, `db/02_logica.sql` y
  `db/03_datos_iniciales.sql`.
- **backend**: API FastAPI en `http://localhost:8081` (docs interactivas en `/docs`).

Con el backend arriba, en otra terminal:

```bash
cd frontend
npm install
npm start          # http://localhost:3000
```

Abrí `http://localhost:3000/login` y entrá con cualquiera de los usuarios de prueba de abajo.

Si ya levantaste el volumen de Postgres antes de tocar los `.sql`, hay que recrearlo para
que los scripts de init corran de nuevo:

```bash
docker compose down -v
docker compose up --build
```

### Usuarios de prueba (creados por `03_datos_iniciales.sql`)

Password de todos: `demo1234`.

| Email                              | Tipo    | Rol / sucursal                  |
|-------------------------------------|---------|----------------------------------|
| admin@fashionstore.bo               | STAFF   | ADMIN — Equipetrol (Santa Cruz)  |
| cajera.scz@fashionstore.bo          | STAFF   | CAJERO — Equipetrol (Santa Cruz) |
| encargada.lapaz@fashionstore.bo     | STAFF   | ENCARGADO — Sopocachi (La Paz)   |
| cajera.lapaz@fashionstore.bo        | STAFF   | CAJERO — Sopocachi (La Paz)      |
| encargado.cbba@fashionstore.bo      | STAFF   | ENCARGADO — Cala Cala (Cochabamba) |
| cajero.cbba@fashionstore.bo         | STAFF   | CAJERO — Cala Cala (Cochabamba)  |
| vendedor.scz@fashionstore.bo        | STAFF   | VENDEDOR — Equipetrol (Santa Cruz) |
| almacen.scz@fashionstore.bo         | STAFF   | ALMACEN — Equipetrol (Santa Cruz) |
| cliente@fashionstore.bo             | CLIENTE | —                                |
| cliente2@fashionstore.bo            | CLIENTE | —                                |

Actores humanos: Cliente, Administrador, Encargado de sucursal (recepciones, ajustes de stock,
confirmar/preparar reservas; puede cubrir la caja), Cajero (venta presencial, cobros,
verificacion de pagos QR/efectivo, cierre de caja), Vendedor (atiende reservas en el piso) y
Almacen (recepciones y ajustes de stock). El
proveedor no es usuario (sus datos los carga el Administrador en CU11). Caja (CU07) y atencion
de reservas (CU08) se autorizan por permiso (`caja.crear` / `reservas.actualizar`), no por
cargo; el ADMIN tambien puede operarlas en su sucursal (Equipetrol).

El catalogo queda poblado con 6 productos de moda femenina (blusa de lino, vestido floral, jean de
tiro alto, tapado de lana, botineta de cuero y chalina de alpaca), 63 variantes por talla/color e
inventario en las 3 sucursales **repartido segun el clima de cada ciudad** (ver Modelo de negocio),
mas 3 promociones de ejemplo (`BIENVENIDA10`, `VERANO15`, `INVIERNO30`).

### Endpoints disponibles

- `POST /auth/login` — autentica y devuelve un JWT.
- `GET /catalogo/productos` — lista productos activos (filtros: `categoria_slug`, `q`, `limit`, `offset`).
- `GET /direcciones` / `POST /envios/cotizar` — libreta de direcciones y tarifa del delivery (CU20).
- `GET /health` — chequeo de salud.
- La lista completa esta en `http://localhost:8081/docs` (OpenAPI).

## Desarrollo del backend sin Docker

Requiere Postgres corriendo (por ejemplo, `docker compose up db` para levantar solo la base en
`localhost:5433`).

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate        # Windows
pip install -r requirements.txt
cp .env.example .env          # ya apunta a localhost:5433; ajustar si Postgres corre en otro lado
uvicorn app.main:app --reload --port 8081
```

## Deploy en Railway

1. Crear un servicio Postgres en Railway y cargar `db/01_schema.sql`, `db/02_logica.sql` y
   (opcional en produccion) `db/03_datos_iniciales.sql` contra esa instancia.
2. Crear un servicio a partir de este repo con **root directory** `backend/` (usa el
   `Dockerfile` incluido).
3. Configurar las variables de entorno del servicio backend: `DATABASE_URL` (la que da Railway
   para el servicio de Postgres) y `JWT_SECRET`.
4. Railway inyecta `PORT` automaticamente; el `Dockerfile` ya lo respeta.

# FashionStore

Plataforma de comercio electronico e inteligencia de tienda para una cadena de ropa
con sucursales en Bolivia. Proyecto de Sistemas II (S2-2026).

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
| Backend (FastAPI)   | http://localhost:8080      |
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
- **backend**: API FastAPI en `http://localhost:8080` (docs interactivas en `/docs`).

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
| encargada.lapaz@fashionstore.bo     | STAFF   | ENCARGADO — Sopocachi (La Paz)   |
| cajero.cbba@fashionstore.bo         | STAFF   | CAJERO — Cala Cala (Cochabamba)  |
| vendedor.scz@fashionstore.bo        | STAFF   | VENDEDOR — Equipetrol (Santa Cruz) |
| cliente@fashionstore.bo             | CLIENTE | —                                |
| cliente2@fashionstore.bo            | CLIENTE | —                                |

El catalogo queda poblado con 6 productos (camisetas, jeans, vestidos, chaquetas, zapatillas y
accesorios) con variantes por talla/color e inventario en las 3 sucursales, mas 2 promociones de
ejemplo (`BIENVENIDA10`, `VERANO15`).

### Endpoints disponibles

- `POST /auth/login` — autentica y devuelve un JWT.
- `GET /catalogo/productos` — lista productos activos (filtros: `categoria_slug`, `q`, `limit`, `offset`).
- `GET /health` — chequeo de salud.

## Desarrollo del backend sin Docker

Requiere Postgres corriendo (por ejemplo, `docker compose up db` para levantar solo la base en
`localhost:5433`).

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate        # Windows
pip install -r requirements.txt
cp .env.example .env          # ya apunta a localhost:5433; ajustar si Postgres corre en otro lado
uvicorn app.main:app --reload --port 8080
```

## Deploy en Railway

1. Crear un servicio Postgres en Railway y cargar `db/01_schema.sql`, `db/02_logica.sql` y
   (opcional en produccion) `db/03_datos_iniciales.sql` contra esa instancia.
2. Crear un servicio a partir de este repo con **root directory** `backend/` (usa el
   `Dockerfile` incluido).
3. Configurar las variables de entorno del servicio backend: `DATABASE_URL` (la que da Railway
   para el servicio de Postgres) y `JWT_SECRET`.
4. Railway inyecta `PORT` automaticamente; el `Dockerfile` ya lo respeta.

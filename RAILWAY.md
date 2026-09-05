# Despliegue en Railway

Este monorepo (`fashionstore/`) se despliega en Railway como **tres servicios** dentro de un
mismo proyecto: el plugin de Postgres, el backend (FastAPI) y el frontend (Angular). Railway no
ejecuta `docker-compose.yml` directamente -- cada servicio se configura por separado apuntando
al mismo repo de GitHub, con un "Root Directory" distinto (`backend/` o `frontend/`) para que
detecte el Dockerfile correspondiente.

Los archivos que ya quedaron preparados para esto:

- `backend/Dockerfile` -- ya escuchaba en `${PORT:-8000}`, sin cambios.
- `backend/railway.toml` -- healthcheck en `/health`, restart on failure.
- `backend/.dockerignore` -- evita copiar `.venv`/`.env` a la imagen.
- `frontend/Dockerfile` -- build de Angular + Nginx sirviendo `dist/fashionstore-frontend/browser`.
- `frontend/default.conf.template` -- config de Nginx con `listen ${PORT}` (Railway inyecta el
  puerto en runtime) y fallback a `index.html` para las rutas de Angular Router.
- `frontend/railway.toml` / `frontend/.dockerignore`.
- `frontend/src/environments/environment.ts` -- `apiUrl` es un placeholder `__API_URL__` que el
  Dockerfile reemplaza en build time con el ARG `API_URL`.
- `db/aplicar_en_railway.sh` -- aplica `01_schema.sql`, `02_logica.sql` y (opcional)
  `03_datos_iniciales.sql` contra una base Postgres externa, sin necesitar `psql` instalado.

## 1. Crear el proyecto y el Postgres

1. En Railway: **New Project → Deploy PostgreSQL** (o "Provision PostgreSQL" dentro de un
   proyecto vacio).
2. Andá a la pestaña **Variables** del servicio Postgres y copiá el valor de
   `DATABASE_PUBLIC_URL` (la URL publica, no `DATABASE_URL` -- esa es solo alcanzable desde la
   red privada de Railway).
3. Aplicá el esquema desde tu maquina (necesita Docker, no necesita `psql`):

   ```bash
   cd fashionstore/db
   ./aplicar_en_railway.sh "postgresql://...la_DATABASE_PUBLIC_URL..."
   ```

   Esto crea las 43 tablas, las vistas/funciones/triggers de `02_logica.sql` y carga los datos
   demo de `03_datos_iniciales.sql` (usuarios de prueba, catalogo, inventario). Si no queres los
   datos demo en el deploy, agregá `--sin-seed` al final del comando.

   Alternativa sin el script: pegar el contenido de cada archivo, en orden, en la pestaña
   **Data → Query** del servicio Postgres en el dashboard de Railway.

## 2. Backend (FastAPI)

1. **New Service → GitHub Repo** (el mismo repo) → en **Settings → Source**, poné
   **Root Directory** = `backend`. Railway detecta `backend/Dockerfile` y `backend/railway.toml`
   solo.
2. En **Variables** del servicio backend, agregá:

   | Variable | Valor |
   |---|---|
   | `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` (referencia a la variable del plugin -- usa la red privada, mas rapido) |
   | `JWT_SECRET` | un secreto random real, **no** el `dev-secret-change-me` de `.env.example` (`openssl rand -hex 32`) |
   | `JWT_ALGORITHM` | `HS256` |
   | `JWT_EXPIRE_MINUTES` | `480` |
   | `CORS_ORIGINS` | `["https://<url-publica-del-frontend>"]` (la completás despues del paso 3, ver abajo) |
   | `FRONTEND_URL` | `https://<url-publica-del-frontend>` (sin `/` final -- la usan las `success_url`/`cancel_url` de Stripe) |
   | `STRIPE_SECRET_KEY` | tu clave de Stripe (test o live) |
   | `STRIPE_PUBLISHABLE_KEY` | idem |
   | `STRIPE_WEBHOOK_SECRET` | ver nota de Stripe mas abajo |

3. Generá el dominio publico en **Settings → Networking → Generate Domain**. Anotá la URL
   (`https://fashionstore-backend-production.up.railway.app` o similar) -- la vas a necesitar
   como `API_URL` del frontend.
4. Probá `https://<esa-url>/health` -- debe responder `{"status":"ok"}`.

**Nota Stripe (CU06):** `stripe listen` es solo para desarrollo local. En produccion, andá a
[Stripe Dashboard → Developers → Webhooks](https://dashboard.stripe.com/webhooks), agregá un
endpoint apuntando a `https://<url-del-backend>/pagos/webhook/stripe`, evento
`checkout.session.completed` (+ `async_payment_succeeded`/`async_payment_failed`/`expired`), y
copiá el "Signing secret" (`whsec_...`) que te muestra ahi -- ese es el `STRIPE_WEBHOOK_SECRET`
de produccion, distinto al que imprime `stripe listen`.

## 3. Frontend (Angular + Nginx)

1. **New Service → GitHub Repo** (mismo repo) → **Root Directory** = `frontend`.
2. En **Variables** del servicio frontend, agregá `API_URL` = la URL publica del backend del
   paso 2 (sin `/` final). Railway pasa las variables del servicio como build args al Dockerfile
   automaticamente, y el `ARG API_URL` de `frontend/Dockerfile` la recoge para hornear el valor
   correcto en `environment.ts` antes de compilar.
3. Generá el dominio publico igual que en el backend.
4. Volvé al servicio backend y completá `CORS_ORIGINS`/`FRONTEND_URL` con esta URL (paso 2 de
   arriba) -- sin esto el navegador bloquea las llamadas del frontend al backend por CORS.

## 4. Verificacion

- Abrí la URL publica del frontend, iniciá sesion con `cliente@fashionstore.bo` / `demo1234` (o
  `admin@fashionstore.bo` para `/atender-reservas`, `cajero.cbba@fashionstore.bo` para `/caja` --
  ver `CLAUDE.md` para la lista completa de usuarios semilla).
- Si algo de CORS/red falla, la consola del navegador (F12) muestra el origen bloqueado --
  revisar que `CORS_ORIGINS` del backend tenga exactamente la URL del frontend (con `https://`,
  sin `/` final).
- Cualquier cambio a los `.sql` de `db/` despues de este primer deploy **no** se re-aplica solo
  (a diferencia de `docker compose down -v` en local) -- hay que correr la migracion a mano
  (`aplicar_en_railway.sh`, o el statement puntual) contra la base de Railway.

## Pendientes conocidos (no bloquean el deploy)

- El job periodico que expira reservas vencidas (`fn_expirar_reservas()`) todavia no esta
  implementado en el backend -- ver la nota de CU04/CU08 en el historial del proyecto. En
  produccion esto significa que una reserva vencida sin atender manualmente (`/atender-reservas`)
  deja el stock comprometido hasta que un Encargado la resuelva o la marque "Cliente no se
  presento".
- `movil/` (Flutter) no forma parte de este despliegue.

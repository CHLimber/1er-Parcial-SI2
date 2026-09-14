# Despliegue en Railway

Este monorepo (`fashionstore/`) se despliega en Railway como **tres servicios** dentro de un
mismo proyecto: el plugin de Postgres, el backend (FastAPI) y el frontend (Angular). La app
movil (`movil/`) no es un servicio de Railway -- se compila localmente, pero el APK de release
apunta al backend desplegado aca (ver seccion 5). Railway no
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
   | `PUBLIC_BASE_URL` | la URL publica de este mismo servicio backend (ver paso 3) -- sin esto las imagenes subidas por CU10 quedan con una URL que apunta a `localhost` |

3. Generá el dominio publico en **Settings → Networking → Generate Domain**. Anotá la URL
   (`https://fashionstore-backend-production.up.railway.app` o similar) -- la vas a necesitar
   como `API_URL` del frontend y como `PUBLIC_BASE_URL` de arriba.
4. Probá `https://<esa-url>/health` -- debe responder `{"status":"ok"}`.
5. **Volume para las imagenes de catalogo (CU10):** en **Settings → Volumes**, agregá un volumen
   montado en `/app/media`. Sin esto, cada imagen subida con el panel de administracion
   (`POST /admin/catalogo/productos/{id}/imagenes/subir`) se pierde en el proximo deploy, porque
   el filesystem del contenedor no es persistente. Las imagenes agregadas por URL externa (el
   endpoint sin `/subir`, o el seed de picsum.photos) no se ven afectadas por esto.

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

## 4. App movil (Flutter)

La app no se despliega en Railway: se compila y se instala como APK. Lo unico que la ata al
deploy es la URL del backend, que vive en `movil/lib/core/config.dart`:

- **release** (`flutter build apk --release`) -> `Config.apiUrlProduccion`, el backend de
  Railway. Es lo que tiene que usar un APK instalado en un telefono real.
- **debug** (`flutter run`) -> el Docker local (`10.0.2.2:8081` desde el emulador).
- `--dart-define=API_URL=...` pisa a los dos, para apuntar a otro deploy sin tocar codigo.

Si se regenera el dominio del backend, hay que cambiar `apiUrlProduccion` y recompilar el APK
(la URL se hornea en build time, igual que el `API_URL` del frontend). La pantalla **Cuenta**
muestra abajo un badge `RAILWAY` / `LOCAL` con la URL activa, para saber contra que base se
esta probando.

Dos cosas que **no** hacen falta para el movil, a diferencia del frontend web:

- **CORS**: una app nativa no manda `Origin`, asi que no hay que agregar nada a `CORS_ORIGINS`.
- **`network_security_config.xml`**: solo existe para permitir HTTP plano contra el backend
  local; contra Railway la app habla HTTPS y esa excepcion no se usa.

**Limitacion conocida (CU06 + Stripe):** `FRONTEND_URL` apunta al frontend web, asi que cuando
un usuario de la app paga con Stripe, la `success_url` lo deja en la **web**, no de vuelta en la
app. La app lo tolera -- queda en `/compra/{venta_id}` con un boton "consultar estado del pago"
y el webhook confirma igual -- pero el regreso automatico al telefono necesitaria un deep link
(`applinks` / esquema propio), que todavia no esta implementado. Con LIBELULA no pasa: el pago
simulado se resuelve dentro de la app.

## 5. Si el panel de gestion responde 403 en el deploy

Sintoma: el login anda y el catalogo carga, pero **todo CU09-CU13 devuelve
`{"detail":"Tu rol no tiene permiso para esta operacion"}`**, incluso con `admin@fashionstore.bo`.
Si se mira el `usuario` que devuelve `/auth/login`, el `rol` esta bien (`ADMIN`) pero
`permisos` viene **vacio**.

Causa: las tablas `permiso` / `rol_permiso` quedaron sin poblar. Pasa cuando
`03_datos_iniciales.sql` se aplico a medias -- y `aplicar_en_railway.sh` es propenso a eso,
porque `db/` esta montado entero en `docker-entrypoint-initdb.d` y el propio `.sh` tambien se
ejecuta ahi en el arranque local. Como la API autoriza por codigo de permiso (CU13), sin esas
filas ningun rol puede hacer nada de gestion.

Arreglo (idempotente, no toca usuarios, catalogo ni inventario):

```bash
cd fashionstore
docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1   < db/reparaciones/permisos_cu13.sql
```

Al final imprime el conteo por rol: tiene que dar **ADMIN 19, ENCARGADO 11, ALMACEN 7,
CAJERO 4, VENDEDOR 3**. Despues hay que **volver a iniciar sesion** (o tocar "actualizar
permisos" en la app movil): el JWT no guarda los permisos, pero la sesion guardada en el
navegador/telefono si, y queda vieja hasta que se refresque con `GET /auth/yo`.

## 6. Verificacion

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
- La app movil no tiene deep link de retorno desde Stripe (ver seccion 4); despues de pagar hay
  que volver a la app y tocar "consultar estado del pago".

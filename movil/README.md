# FashionStore movil (Flutter)

App Android/iOS que cubre los mismos casos de uso que la web (CU01 a CU14, CU17, CU18 y CU20),
mas el vestidor virtual con realidad aumentada (CU16, que solo existe aca), contra la misma
API de FastAPI. No tiene logica de negocio propia: la fuente de verdad sigue siendo la base
de datos (`db/01_schema.sql`, `db/02_logica.sql`) y el backend.

## Correr la app en local

Pasos completos desde cero. La app no sirve de nada sin el backend: lo primero
siempre es levantarlo.

### 1. Levantar el backend y la base

Desde `fashionstore/` (no desde `movil/`):

```bash
docker compose up --build        # Postgres en 5433 + backend en 8081
```

Comprobar que responde antes de seguir:

```bash
curl http://localhost:8081/health     # -> {"status":"ok"}
```

Si el backend no levanta, casi siempre es que falta `backend/.env`
(`docker-compose.yml` lo carga con `env_file`): copiar `backend/.env.example` y
completarlo. Si cambiaste algun `.sql` de `db/`, hay que recrear el volumen con
`docker compose down -v` para que corran los scripts de init otra vez.

### 2. Preparar el emulador de Android

```bash
flutter emulators                        # lista los emuladores creados
flutter emulators --launch Pixel_10a     # o el id que tengas
flutter devices                          # el emulador tiene que aparecer aca
```

Si no hay ninguno, se crea con `flutter emulators --create` o desde el Device
Manager de Android Studio.

**Solo para la realidad aumentada de CU16** (el boton "ver en tu espacio"): el
emulador no trae "Google Play Services para RA" y sin esa app el AR no arranca.
El visor 3D de la app funciona igual sin ella, asi que esto es opcional. Google
publica el APK para emulador en las releases del SDK:

```bash
curl -L -o arcore.apk https://github.com/google-ar/arcore-android-sdk/releases/download/1.56.0/Google_Play_Services_for_AR_1.56.0_x86_for_emulator.apk
adb install -r -t arcore.apk
```

En un telefono real se instala desde la Play Store. Ojo con los equipos **sin
servicios de Google** (los Huawei posteriores al veto, por ejemplo): ahi no hay
ARCore de ninguna forma y solo queda el visor 3D, que es justamente por lo que el
visor vive dentro de la app y no se delega todo a Scene Viewer.

### 3. Correr la app

Desde `movil/`:

```bash
flutter pub get      # solo la primera vez o al cambiar pubspec.yaml
flutter run          # debug -> backend local (10.0.2.2:8081)
```

Con la app corriendo, `r` recarga en caliente, `R` reinicia y `q` sale.

Entrar con cualquiera de los usuarios semilla (password `demo1234` para todos):

| Usuario | Para probar |
|---|---|
| `cliente@fashionstore.bo` | CU03 a CU06: catalogo, reservas, carrito, pago |
| `admin@fashionstore.bo` | el panel completo, CU09 a CU13 |
| `encargada.lapaz@fashionstore.bo` | CU08, atender reservas de La Paz |
| `cajero.cbba@fashionstore.bo` | CU07, caja de Cochabamba |
| `almacen.scz@fashionstore.bo` | CU09, recepciones (rol sin acceso al resto) |

La pantalla **Cuenta** muestra abajo un badge `LOCAL` / `RAILWAY` con la URL
activa: sirve para confirmar de un vistazo contra que base estas probando.

### Otros comandos

```bash
flutter test                  # 3 pruebas: login, validacion y bolsa de reserva
flutter analyze               # tiene que dar "No issues found!"
flutter build apk --debug     # APK para instalar a mano (apunta al backend local)
flutter build apk --release   # APK de produccion (apunta a Railway)
```

### APK para instalar en un telefono

Para un telefono real conviene el build **partido por arquitectura**: el APK
"universal" mete las tres (`arm64-v8a`, `armeabi-v7a`, `x86_64`) en el mismo
archivo y pesa ~122 MB, de los cuales el telefono usa un tercio.

```bash
flutter build apk --release --split-per-abi
```

Deja tres archivos en `build/app/outputs/flutter-apk/`:

| Archivo | Peso | Para que |
|---|---|---|
| `app-arm64-v8a-release.apk` | ~65 MB | **el que se instala en un celular** (cualquiera de los ultimos ~10 anios) |
| `app-armeabi-v7a-release.apk` | ~59 MB | telefonos viejos de 32 bits |
| `app-x86_64-release.apk` | ~68 MB | el emulador de Android |

El peso lo dominan las `.so`: `libflutter.so` mas el motor de ML Kit
(`libxeno_native.so`, ~10 MB) que trae la deteccion de pose del vestidor virtual
(CU16). No se achica apagando cosas del lado de Dart.

Para instalar un APK ya compilado en el emulador o en un telefono conectado:

```bash
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

(`adb` esta en `%LOCALAPPDATA%\Android\sdk\platform-tools`.)

### Contra que backend habla

`Config` (en `lib/core/config.dart`) resuelve la URL en este orden:

| Como se compila | URL |
|---|---|
| `--dart-define=API_URL=...` | la que pases (gana siempre) |
| `flutter build apk --release` | `Config.apiUrlProduccion` -> el backend en Railway |
| `flutter run` (debug) | `http://10.0.2.2:8081`, el Docker local |

En el emulador de Android `localhost` es el propio emulador, no la maquina: por
eso en debug se usa `10.0.2.2`. Para probar en **debug contra un telefono
fisico** hay que pasar la IP de la maquina en la red local y agregarla como
dominio en `android/app/src/main/res/xml/network_security_config.xml` (Android 9+
bloquea HTTP sin TLS salvo los hosts declarados ahi):

```bash
flutter run --dart-define=API_URL=http://192.168.0.10:8081
```

Contra Railway nada de eso hace falta: la API va por HTTPS. Si se regenera el
dominio del backend, hay que actualizar `Config.apiUrlProduccion` y recompilar
el APK. El despliegue esta documentado en `../RAILWAY.md`.

### Si algo no anda

| Sintoma | Causa habitual |
|---|---|
| "No se pudo conectar con http://10.0.2.2:8081" | el backend local no esta levantado, o `docker compose` se cayo |
| La app abre pero el catalogo queda vacio | la base se recreo sin seed: `docker compose down -v && docker compose up --build` |
| 403 en las pantallas del panel | el rol del usuario no tiene ese permiso (CU13), o los permisos de la base estan sin sembrar |
| El build falla por el NDK | falta instalar el NDK que fija `android/app/build.gradle.kts` (SDK Manager -> NDK 28.2.13676358) |
| El APK de release instala pero la app **no abre** (se cierra sin mostrar nada) | R8: ver "Notas del entorno Android". Confirmarlo con `adb logcat` mientras se abre la app; el stack dice `Unable to get provider androidx.startup.InitializationProvider` |

## Estructura

```
lib/
├── main.dart                 # arranque: restaura la sesion y monta los providers
├── rutas.dart                # go_router + guards (espejo de app.routes.ts de Angular)
├── core/<dominio>/           # modelos y servicios, en espejo con los modulos del backend
│   ├── api.dart              # cliente HTTP unico (token + traduccion de errores)
│   ├── config.dart           # apiUrl y formato de moneda
│   ├── errores.dart          # interpreta el `detail` de FastAPI
│   └── tema.dart             # paleta ink/paper/flame/gold de la web
├── paginas/                  # una pantalla por archivo
└── compartido/               # widgets transversales y barra de navegacion
```

Los modelos de `core/*/` son un espejo manual de los schemas Pydantic del backend: si un
schema cambia, hay que actualizarlos a mano (igual que los `.models.ts` del frontend).

El estado va con `ChangeNotifier` + `provider` (no hay store global). `AuthService`,
`ReservaCarritoService` y `CarritoService` son los tres notificadores compartidos; el resto
de servicios son objetos sin estado que solo hablan con la API.

## Que pantalla cubre cada CU

| CU | Pantalla | Ruta |
|----|----------|------|
| CU01 Iniciar sesion | `login_pagina.dart` | `/login` |
| CU02 Registrarse | `registro_pagina.dart` | `/registro` |
| CU03 Consultar catalogo | `tienda_pagina.dart`, `producto_detalle_pagina.dart` | `/tienda`, `/producto/:slug` |
| CU04 Reservar prendas | `reservar_pagina.dart`, `mis_reservas_pagina.dart` | `/reservar`, `/mis-reservas` |
| CU05 Comprar por web/app | `carrito_pagina.dart` | `/carrito` |
| CU06 Procesar y confirmar pago | `pago_simulado_pagina.dart`, `compra_pagina.dart` | `/pago-simulado/:id`, `/compra/:id` |
| CU07 Registrar venta presencial | `caja_pagina.dart` | `/caja` |
| CU08 Atender reserva | `atender_reservas_pagina.dart` | `/atender-reservas` |
| CU09 Registrar recepcion | `panel_recepciones_pagina.dart` | `/panel/recepciones` |
| CU10 Gestionar catalogo | `panel_catalogo_pagina.dart` | `/panel/catalogo` |
| CU11 Gestionar proveedores | `panel_proveedores_pagina.dart` | `/panel/proveedores` |
| CU12 Gestionar sucursales | `panel_sucursales_pagina.dart` | `/panel/sucursales` |
| CU13 Gestionar usuarios y roles | `panel_usuarios_pagina.dart` | `/panel/usuarios` |
| CU16 Vestidor virtual (RA) | `vestidor_virtual_pagina.dart` | desde el detalle de producto |
| CU17 Recibir recomendaciones de IA | `tienda_pagina.dart` (seccion "Recomendado para vos") | `/tienda` |
| CU18 Asistir al cliente via chatbot (con dictado por voz) | `asistente_pagina.dart` | `/asistente` |
| CU20 Entrega a domicilio | `mis_direcciones_pagina.dart`, `panel_envios_pagina.dart` | `/mis-direcciones`, `/panel/envios` |

La barra inferior tiene las cuatro pantallas de uso diario del cliente (Tienda, Reservas,
Carrito, Cuenta). Las pantallas de personal (CU07, CU08 y el panel CU09-CU13 y CU20) se abren
desde **Cuenta**, y solo aparecen si el usuario es STAFF. La libreta de direcciones de CU20
tambien cuelga de **Cuenta**, pero del lado del cliente.

Para probar CU20 de punta a punta: con `cliente@fashionstore.bo` guarda una direccion (viene
una de fabrica), elegi "A domicilio" en el carrito, pagas con Libelula (la pantalla de pago
simulado confirma el webhook) y despues entras con `admin@fashionstore.bo` para marcarlo
DESPACHADO y despues ENTREGADO desde **Cuenta > Envios**. El reparto en si lo hace un
servicio de delivery externo -- la app solo registra esos dos momentos, no una hoja de ruta.

## Autorizacion

Igual que en la web, la app arma el menu con los **codigos de permiso** del rol
(`UsuarioOut.permisos`), no con el nombre del rol: `permisoGuard` vive en `rutas.dart`
(`_permisosPorRuta`) y `AuthService.tienePermiso()` decide que botones se muestran dentro
de cada pantalla. Eso solo evita mostrar pantallas inutiles: **quien autoriza siempre es la
API**. CU07 y CU08 siguen validandose por cargo en el backend
(`get_cajero_actual` / `get_encargado_actual`), asi que sus rutas no exigen permiso local y
es la API la que responde 403.

`Cuenta > actualizar permisos` (el icono de sincronizar) llama a `GET /auth/yo`: hace falta
cuando el administrador cambia un rol o sus permisos mientras la sesion esta abierta.

## Pagos (CU06)

`POST /ventas/checkout` se manda siempre con `canal: MOVIL`. Segun la pasarela:

- **STRIPE**: `url_pago` es una URL absoluta de `checkout.stripe.com`, que se abre en el
  navegador del telefono con `url_launcher`. La app queda en `/compra/{venta_id}` con un
  boton para volver a consultar el estado, porque la confirmacion llega por webhook firmado
  desde los servidores de Stripe.
- **LIBELULA**: `url_pago` es la ruta interna `/pago-simulado/{venta_id}`, que aca se
  resuelve con una pantalla nativa que manda el resultado a
  `POST /pagos/webhook/LIBELULA` (idempotente por `evento_id`).

En los dos casos el detalle de la venta se escribe recien cuando el pago se aprueba.

## Notas del entorno Android

- `android/app/build.gradle.kts` fija `ndkVersion = "28.2.13676358"`, que es el que piden los
  plugins nativos y el que Gradle usa para hacer `strip` de las `.so` del release. Si falta,
  se instala desde el SDK Manager en vez de apuntar a otra version "compatible".
- **R8 apagado en release** (`isMinifyEnabled = false`). El proyecto usa AGP 9, que lo
  enciende por defecto (AGP 8 no lo hacia), y con R8 el APK instalaba pero la app moria
  antes del primer frame:

  ```
  java.lang.RuntimeException: Unable to get provider androidx.startup.InitializationProvider
  Caused by: Failed to create an instance of androidx.work.impl.WorkDatabase
  ```

  WorkManager entra por `google_mlkit_pose_detection` (CU16) y su base Room se instancia por
  reflexion (`WorkDatabase_Impl`); R8 le cambia el nombre, la clase deja de existir y el
  `ContentProvider` de `androidx.startup` explota al crear el proceso, antes de que corra una
  sola linea de Dart. Por eso solo pasaba en release. Volver a encenderlo exigiria reglas
  `-keep` para Room, WorkManager, ML Kit y Stripe, y cada plugin nuevo con reflexion seria
  otra bomba de tiempo que solo se nota al instalar el APK; a cambio ahorra ~13 MB de dex
  sobre un APK cuyo peso son las `.so`. Para achicar de verdad se usa `--split-per-abi`.
- El manifiesto declara `INTERNET`, el `network_security_config` para HTTP local y la query
  de `VIEW https` que `url_launcher` necesita en Android 11+.

import 'dart:io';

import 'package:flutter/foundation.dart';

/// URL base de la API de FashionStore.
///
/// Se resuelve en este orden:
///
/// 1. `--dart-define=API_URL=...` si se paso al compilar (gana siempre; sirve para probar
///    contra un telefono fisico apuntando a la IP de la maquina, o contra otro deploy).
/// 2. En **release**, el backend desplegado en Railway (ver `fashionstore/RAILWAY.md`), que
///    es el que tiene que usar un APK instalado en un telefono real.
/// 3. En **debug**, el backend local de `docker compose up`. Desde el emulador de Android
///    `localhost` es el propio emulador, no la maquina, por eso 10.0.2.2.
///
/// ```bash
/// flutter run                                              # debug  -> Docker local
/// flutter build apk --release                              # release -> Railway
/// flutter run --dart-define=API_URL=http://192.168.0.10:8081   # telefono fisico -> tu maquina
/// ```
class Config {
  /// Backend en Railway (servicio `backend`, dominio publico generado en Settings →
  /// Networking). Si se regenera el dominio, se cambia aca.
  static const String apiUrlProduccion = 'https://backend-production-765b9.up.railway.app';

  static const String _apiUrlDefinida = String.fromEnvironment('API_URL');

  static String get apiUrl {
    if (_apiUrlDefinida.isNotEmpty) return _apiUrlDefinida;
    if (kReleaseMode) return apiUrlProduccion;
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8081';
    return 'http://localhost:8081';
  }

  /// True cuando la app esta hablando con el deploy de Railway y no con el Docker local.
  /// La pantalla de Cuenta lo muestra para que no haya dudas de contra que base se probo.
  static bool get apuntaAProduccion => apiUrl == apiUrlProduccion;

  /// Moneda fija del proyecto (BOB) e IVA 13% viven en la base, aca solo se formatea.
  static const String simboloMoneda = 'Bs';
}

String formatearPrecio(num precio) => '${Config.simboloMoneda} ${precio.toStringAsFixed(2)}';

/// Bases conocidas de `settings.public_base_url` (backend/app/core/config.py) con las que
/// el backend arma sus `imagen_url` absolutas (CU10, `app/core/media.py`). Esa base es la
/// que ve el SERVIDOR de si mismo -- en dev siempre `http://localhost:8081` -- y no coincide
/// con la que usa el cliente real (`Config.apiUrl`) en el emulador de Android ni en un
/// telefono fisico apuntando por IP.
const _basesMediaConocidas = ['http://localhost:8081', 'http://127.0.0.1:8081'];

/// Reescribe una `imagen_url` del backend a la base que esta plataforma puede alcanzar.
///
/// Sin esto, en el emulador de Android `http://localhost:8081/media/...` apunta al propio
/// emulador (no hay nada ahi) y las fotos reales de las 40 prendas del catalogo (subidas via
/// CU10) nunca cargan: `Image.network` cae siempre al placeholder. Una URL externa autentica
/// (pegada a mano en el panel, o un host que no es el backend) se devuelve intacta.
String? resolverUrlMedia(String? url) {
  if (url == null || url.isEmpty) return null;
  for (final base in _basesMediaConocidas) {
    if (url.startsWith(base)) return '${Config.apiUrl}${url.substring(base.length)}';
  }
  return url;
}

/// CU16 nivel 2: la URL del modelo 3D tal como la necesita un visor EXTERNO.
///
/// El visor embebido de la app (`Visor3dPagina`) puede leer el GLB por HTTP plano,
/// porque el WebView es nuestro y hereda `network_security_config.xml`. Google Scene
/// Viewer no: es otra app, exige HTTPS para el `file=` y no tiene forma de alcanzar el
/// `10.0.2.2:8081` del Docker local. Por eso, cuando la URL no es HTTPS, se sirve el
/// mismo archivo desde el deploy publico de Railway -- los GLB son los del seed, asi
/// que el binario es identico en las dos bases.
String resolverUrlModeloAr(String url) {
  if (url.startsWith('https://')) return url;
  final ruta = url.indexOf('/media/');
  if (ruta == -1) return url;
  return '${Config.apiUrlProduccion}${url.substring(ruta)}';
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Multi-tenant: que tienda (empresa) se esta mirando. Espejo de
/// `frontend/src/app/core/tenant/tienda.ts`. Cada request viaja con el header `X-Empresa`
/// ([ApiClient]): para el personal es siempre su empresa (la del token, el backend igual la
/// impone); para una clienta, la tienda elegida en la vitrina. Se recuerda en
/// SharedPreferences para que al reabrir la app siga en la misma tienda.
const tiendaPorDefecto = 'fashionstore';
const _clave = 'fashionstore.tienda';

final ValueNotifier<String> tiendaActual = ValueNotifier(tiendaPorDefecto);

Future<void> cargarTienda() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    tiendaActual.value = prefs.getString(_clave) ?? tiendaPorDefecto;
  } catch (_) {
    // sin almacenamiento: vale la tienda por defecto
  }
}

Future<void> elegirTienda(String slug) async {
  tiendaActual.value = slug;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clave, slug);
  } catch (_) {}
}

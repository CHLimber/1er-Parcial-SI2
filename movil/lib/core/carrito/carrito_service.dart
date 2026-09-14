import 'package:flutter/foundation.dart';

import '../api.dart';
import '../config.dart';

/// Espejo de `backend/app/modules/carrito/schemas.py` (CU05).
class CarritoItemOut {
  CarritoItemOut({
    required this.id,
    required this.varianteId,
    required this.sku,
    required this.producto,
    required this.productoSlug,
    required this.talla,
    required this.color,
    required this.codigoHex,
    required this.imagenUrl,
    required this.precioUnitario,
    required this.cantidad,
    required this.subtotal,
  });

  final String id;
  final String varianteId;
  final String sku;
  final String producto;
  final String productoSlug;
  final String talla;
  final String color;
  final String codigoHex;
  final String? imagenUrl;
  final double precioUnitario;
  final int cantidad;
  final double subtotal;

  factory CarritoItemOut.desdeJson(Map<String, dynamic> j) => CarritoItemOut(
        id: j['id'] as String,
        varianteId: j['variante_id'] as String,
        sku: j['sku'] as String,
        producto: j['producto'] as String,
        productoSlug: j['producto_slug'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        codigoHex: j['codigo_hex'] as String,
        imagenUrl: resolverUrlMedia(j['imagen_url'] as String?),
        precioUnitario: aDouble(j['precio_unitario']),
        cantidad: aEntero(j['cantidad']),
        subtotal: aDouble(j['subtotal']),
      );
}

class CarritoOut {
  CarritoOut({
    required this.id,
    required this.estado,
    required this.reservaId,
    required this.reservaCodigo,
    required this.items,
    required this.cantidadItems,
    required this.subtotal,
  });

  final String id;
  final String estado;
  final String? reservaId;
  final String? reservaCodigo;
  final List<CarritoItemOut> items;
  final int cantidadItems;
  final double subtotal;

  factory CarritoOut.desdeJson(Map<String, dynamic> j) => CarritoOut(
        id: j['id'] as String,
        estado: j['estado'] as String,
        reservaId: j['reserva_id'] as String?,
        reservaCodigo: j['reserva_codigo'] as String?,
        items: comoLista(j['items']).map(CarritoItemOut.desdeJson).toList(),
        cantidadItems: aEntero(j['cantidad_items']),
        subtotal: aDouble(j['subtotal']),
      );
}

/// Carrito de compra online (CU05). A diferencia del carrito de reserva, este vive en el
/// backend: cada operacion devuelve el carrito completo ya recalculado.
class CarritoService extends ChangeNotifier {
  int _cantidadItems = 0;
  int get cantidadItems => _cantidadItems;

  CarritoOut _registrar(dynamic respuesta) {
    final carrito = CarritoOut.desdeJson(respuesta as Map<String, dynamic>);
    _cantidadItems = carrito.cantidadItems;
    notifyListeners();
    return carrito;
  }

  /// Refresca el contador del icono sin romper la pantalla si falla (sesion recien abierta).
  Future<void> refrescar() async {
    try {
      await verCarrito();
    } catch (_) {
      _cantidadItems = 0;
      notifyListeners();
    }
  }

  void reiniciar() {
    _cantidadItems = 0;
    notifyListeners();
  }

  Future<CarritoOut> verCarrito() async => _registrar(await api.get('/carrito'));

  Future<CarritoOut> agregarItem(String varianteId, int cantidad) async => _registrar(
        await api.post('/carrito/items', cuerpo: {
          'variante_id': varianteId,
          'cantidad': cantidad,
        }),
      );

  Future<CarritoOut> actualizarCantidad(String itemId, int cantidad) async =>
      _registrar(await api.patch('/carrito/items/$itemId', cuerpo: {'cantidad': cantidad}));

  Future<CarritoOut> quitarItem(String itemId) async =>
      _registrar(await api.delete('/carrito/items/$itemId'));

  /// CU05 desde una reserva: arma el carrito con lo que el cliente ya tiene comprometido.
  Future<CarritoOut> crearDesdeReserva(String reservaId) async =>
      _registrar(await api.post('/carrito/desde-reserva/$reservaId'));
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reservas_models.dart';

/// Bolsa de prendas a reservar (CU04). Vive solo en el dispositivo hasta que el cliente
/// confirma la reserva: recien ahi el backend compromete stock. Espejo de
/// `ReservaCarritoService` del frontend.
class ReservaCarritoService extends ChangeNotifier {
  static const String _clave = 'fashionstore.reserva_carrito';

  List<ItemCarritoReserva> _items = [];

  List<ItemCarritoReserva> get items => List.unmodifiable(_items);
  int get cantidadTotal => _items.fold(0, (suma, item) => suma + item.cantidad);
  double get subtotal => _items.fold(0, (suma, item) => suma + item.precio * item.cantidad);
  bool get estaVacio => _items.isEmpty;

  Future<void> inicializar() async {
    final prefs = await SharedPreferences.getInstance();
    final crudo = prefs.getString(_clave);
    if (crudo == null) return;
    try {
      final lista = jsonDecode(crudo) as List;
      _items = lista
          .cast<Map<String, dynamic>>()
          .map(ItemCarritoReserva.desdeJson)
          .toList();
      notifyListeners();
    } catch (_) {
      await prefs.remove(_clave);
    }
  }

  void agregar(ItemCarritoReserva item) {
    final indice = _items.indexWhere((i) => i.varianteId == item.varianteId);
    if (indice >= 0) {
      final existente = _items[indice];
      _items[indice] = existente.copiarCon(cantidad: existente.cantidad + item.cantidad);
    } else {
      _items = [..._items, item];
    }
    _guardar();
  }

  void actualizarCantidad(String varianteId, int cantidad) {
    final indice = _items.indexWhere((i) => i.varianteId == varianteId);
    if (indice < 0) return;
    _items[indice] = _items[indice].copiarCon(cantidad: cantidad);
    _guardar();
  }

  void quitar(String varianteId) {
    _items = _items.where((i) => i.varianteId != varianteId).toList();
    _guardar();
  }

  void limpiar() {
    _items = [];
    _guardar();
  }

  Future<void> _guardar() async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_items.isEmpty) {
      await prefs.remove(_clave);
      return;
    }
    await prefs.setString(_clave, jsonEncode(_items.map((i) => i.aJson()).toList()));
  }
}

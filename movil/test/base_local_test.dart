import 'package:flutter_test/flutter_test.dart';
import 'package:fashionstore_movil/core/operacion_sin_conexion/offline/base_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Base local SQLite del Segundo parcial (PENDIENTES 5.3): cache de respuestas y cola de
/// operaciones sin red. Corre contra SQLite real en memoria (sqflite_common_ffi), sin emulador.
void main() {
  sqfliteFfiInit();

  late BaseLocal base;
  setUp(() => base = BaseLocal(fabrica: databaseFactoryFfi, ruta: inMemoryDatabasePath));

  test('guarda la respuesta de una ruta y la devuelve con la fecha', () async {
    expect(await base.leerRespuesta('/catalogo/productos'), isNull);
    await base.guardarRespuesta('/catalogo/productos', [
      {'nombre': 'Vestido', 'precio': '199.00'},
    ]);
    final guardada = await base.leerRespuesta('/catalogo/productos');
    expect(guardada, isNotNull);
    expect((guardada!.$1 as List).first['nombre'], 'Vestido');
    expect(DateTime.now().difference(guardada.$2).inSeconds, lessThan(5));
  });

  test('guardar de nuevo la misma ruta reemplaza la anterior', () async {
    await base.guardarRespuesta('/carrito', {'cantidad_items': 1});
    await base.guardarRespuesta('/carrito', {'cantidad_items': 3});
    expect((await base.leerRespuesta('/carrito'))!.$1['cantidad_items'], 3);
  });

  test('la cola respeta el orden y se puede vaciar de a una', () async {
    await base.encolar(metodo: 'POST', ruta: '/carrito/items', cuerpo: {'variante_id': 'a'}, descripcion: 'uno');
    await base.encolar(metodo: 'POST', ruta: '/carrito/items', cuerpo: {'variante_id': 'b'}, descripcion: 'dos');
    final pendientes = await base.pendientes();
    expect(pendientes.map((p) => p.cuerpo['variante_id']), ['a', 'b']);
    await base.quitar(pendientes.first.id);
    expect((await base.pendientes()).single.descripcion, 'dos');
  });

  test('limpiar (al cerrar sesion) borra cache y cola', () async {
    await base.guardarRespuesta('/ventas', []);
    await base.encolar(metodo: 'POST', ruta: '/carrito/items', descripcion: 'x');
    await base.limpiar();
    expect(await base.leerRespuesta('/ventas'), isNull);
    expect(await base.pendientes(), isEmpty);
  });
}

import 'dart:io';

import 'package:fashionstore_movil/core/offline/base_local.dart';
import 'package:fashionstore_movil/core/sincronizacion/sincronizacion_models.dart';
import 'package:fashionstore_movil/core/sincronizacion/sincronizacion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Modulos C y D en el movil: paquete offline y operaciones en SQLite real (sqflite_common_ffi),
/// sin emulador. Cubre lo que pide la consigna: reiniciar la app sin perder lo registrado,
/// integridad referencial del paquete y que una operacion no desaparece por enviarse (RN12).
void main() {
  sqfliteFfiInit();

  const usuario = '11111111-1111-4111-8111-111111111111';
  final paquete = <String, dynamic>{
    'generado_en': '2026-10-18T10:00:00Z',
    'empresa_id': 'e0000000-0000-4000-8000-000000000001',
    'empresa': 'FashionStore',
    'sucursal': {'id': 's1', 'codigo': 'SC-01', 'nombre': 'Equipetrol', 'hora_apertura': null, 'hora_cierre': null},
    'sesion_caja_id': 'caja-1',
    'iva_tasa': 0.13,
    'productos': [
      {
        'id': 'p1',
        'codigo': 'VES-01',
        'nombre': 'Vestido lino',
        'slug': 'vestido-lino',
        'categoria': 'Vestidos',
        'imagen_url': null,
        'precio_base': 199.9,
        'variantes': [
          {'id': 'v1', 'sku': 'VES-01-S-NEG', 'talla': 'S', 'color': 'Negro', 'codigo_hex': '#000000', 'precio': 199.9, 'disponible': 3},
          {'id': 'v2', 'sku': 'VES-01-M-NEG', 'talla': 'M', 'color': 'Negro', 'codigo_hex': '#000000', 'precio': 199.9, 'disponible': 1},
        ],
      },
    ],
    'clientes': [
      {'id': 'c1', 'nombre': 'Ana Perez', 'email': 'ana@demo.bo', 'telefono': null},
    ],
  };

  late Directory carpeta;
  late String ruta;
  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('fs_offline_');
    ruta = '${carpeta.path}/local.db';
  });
  tearDown(() async {
    try {
      await carpeta.delete(recursive: true);
    } catch (_) {}
  });

  BaseLocal abrir() => BaseLocal(fabrica: databaseFactoryFfi, ruta: ruta);

  Future<void> registrarVenta(BaseLocal base, String id, {String estado = 'REGISTRADA'}) =>
      base.guardarOperacion(
        {
          'id': id,
          'tipo': 'VENTA',
          'empresa_id': paquete['empresa_id'],
          'sucursal_id': 's1',
          'usuario_id': usuario,
          'registrada_en': DateTime.now().toUtc().toIso8601String(),
          'estado': estado,
          'descripcion': 'Venta: 2x Vestido lino S/Negro',
          'total': 451.77,
          'metodo_pago': 'EFECTIVO',
          'sesion_caja_id': 'caja-1',
        },
        [
          {'variante_id': 'v1', 'cantidad': 2, 'precio_unitario': 199.9, 'descripcion': 'Vestido lino S/Negro'},
        ],
      );

  test('el paquete se guarda con sus variantes y clientas, y se lee por usuario', () async {
    final base = abrir();
    await base.guardarPaquete(paquete, usuario);
    final leido = await base.leerPaquete(usuario);
    expect(leido, isNotNull);
    final (sucursal, productos, variantes, clientes) = leido!;
    expect(sucursal['nombre'], 'Equipetrol');
    expect(productos.single['nombre'], 'Vestido lino');
    expect(variantes.map((v) => v['id']), ['v1', 'v2']);
    expect(clientes.single['email'], 'ana@demo.bo');
    expect(await base.leerPaquete('otro-usuario'), isNull);
  });

  test('volver a descargar reemplaza el paquete entero (cascada, sin restos)', () async {
    final base = abrir();
    await base.guardarPaquete(paquete, usuario);
    final nuevo = Map<String, dynamic>.from(paquete)
      ..['productos'] = <Map<String, dynamic>>[]
      ..['clientes'] = <Map<String, dynamic>>[];
    await base.guardarPaquete(nuevo, usuario);
    final (_, productos, variantes, clientes) = (await base.leerPaquete(usuario))!;
    expect(productos, isEmpty);
    expect(variantes, isEmpty);
    expect(clientes, isEmpty);
  });

  test('una venta registrada sobrevive a reiniciar la app (otra conexion al mismo archivo)', () async {
    final antes = abrir();
    await antes.guardarPaquete(paquete, usuario);
    await registrarVenta(antes, 'op-1');
    await antes.descontarExistencias({'v1': 2});

    final despues = abrir(); // "reiniciar": se abre la base de nuevo desde el disco
    final ops = (await despues.operaciones(usuario)).map(OperacionLocal.desdeFila).toList();
    expect(ops.single.id, 'op-1');
    expect(ops.single.estado, EstadoLocal.registrada);
    expect(ops.single.lineas.single.cantidad, 2);
    final (_, _, variantes, _) = (await despues.leerPaquete(usuario))!;
    expect(variantes.firstWhere((v) => v['id'] == 'v1')['disponible'], 1);
  });

  test('las existencias locales nunca bajan de cero', () async {
    final base = abrir();
    await base.guardarPaquete(paquete, usuario);
    await base.descontarExistencias({'v2': 5});
    final (_, _, variantes, _) = (await base.leerPaquete(usuario))!;
    expect(variantes.firstWhere((v) => v['id'] == 'v2')['disponible'], 0);
  });

  test('cerrar sesion borra cache y paquete pero NO las operaciones (RN12)', () async {
    final base = abrir();
    await base.guardarPaquete(paquete, usuario);
    await registrarVenta(base, 'op-1');
    await base.limpiar();
    expect(await base.leerPaquete(usuario), isNull);
    expect((await base.operaciones(usuario)).single['id'], 'op-1');
  });

  test('la respuesta del servidor actualiza estado y resultado juntos', () async {
    final base = abrir();
    await registrarVenta(base, 'op-1', estado: 'ENVIADA');
    await base.guardarResultado('op-1', {
      'estado': 'CONFLICTO',
      'codigo_motivo': 'STOCK_INSUFICIENTE',
      'motivo': 'Quedan 1 unidad(es)',
      'resultado': null,
      'duplicada': 0,
      'intentos': 1,
      'recibida_en': '2026-10-18T10:05:00Z',
      'actualizado_en': DateTime.now().toIso8601String(),
    });
    final op = OperacionLocal.desdeFila((await base.operaciones(usuario)).single);
    expect(op.estado, EstadoLocal.conflicto);
    expect(op.codigoMotivo, 'STOCK_INSUFICIENTE');
  });

  test('archivar solo saca confirmadas y rechazadas; pendientes y conflictos quedan', () async {
    final base = abrir();
    await registrarVenta(base, 'pendiente');
    await registrarVenta(base, 'enviada', estado: 'ENVIADA');
    await registrarVenta(base, 'conflicto', estado: 'CONFLICTO');
    await registrarVenta(base, 'confirmada', estado: 'CONFIRMADA');
    await registrarVenta(base, 'rechazada', estado: 'RECHAZADA');
    expect(await base.archivarCerradas(usuario), 2);
    final ids = (await base.operaciones(usuario)).map((f) => f['id']).toSet();
    expect(ids, {'pendiente', 'enviada', 'conflicto'});
  });

  test('un estado invalido lo rechaza SQLite (CHECK)', () async {
    final base = abrir();
    expect(() => registrarVenta(base, 'x', estado: 'PERDIDA'), throwsA(isA<DatabaseException>()));
  });

  test('el JSON que se manda a /sync/operaciones respeta OperacionIn', () async {
    final base = abrir();
    await registrarVenta(base, 'op-1');
    final json = OperacionLocal.desdeFila((await base.operaciones(usuario)).single).aJson();
    expect(json['tipo'], 'VENTA');
    expect(json['usuario_id'], usuario);
    expect((json['registrada_en'] as String).endsWith('Z'), isTrue);
    final venta = json['venta'] as Map<String, dynamic>;
    expect(venta['metodo_pago'], 'EFECTIVO');
    expect(venta['total'], '451.77');
    expect((venta['items'] as List).single['precio_unitario'], '199.90');
    expect(json.containsKey('reserva'), isFalse);
  });

  test('total con IVA igual que el backend y UUID v4 valido', () {
    expect(totalConIva([(199.9, 2)]), 451.77);
    final id = nuevoUuid();
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id), isTrue);
    expect(nuevoUuid(), isNot(id));
  });
}

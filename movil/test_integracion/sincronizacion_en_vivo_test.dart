// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fashionstore_movil/core/api.dart';
import 'package:fashionstore_movil/core/operacion_sin_conexion/offline/base_local.dart';
import 'package:fashionstore_movil/core/operacion_sin_conexion/offline/conexion_service.dart';
import 'package:fashionstore_movil/core/operacion_sin_conexion/sincronizacion/sincronizacion_models.dart';
import 'package:fashionstore_movil/core/operacion_sin_conexion/sincronizacion/sincronizacion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ciclo completo del Modulo C contra un backend REAL (no corre con `flutter test` a secas):
///   descargar -> operar sin red -> reiniciar la app -> sincronizar -> ver el resultado,
/// mas el reenvio idempotente (RN11) y un conflicto de stock (RN09).
///
///   flutter test test_integracion --dart-define=API_URL=http://localhost:8081
///
/// Usa el admin demo (admin@fashionstore.bo, demo1234): tiene caja y reservas en Equipetrol.
class _ConectividadFija implements Connectivity {
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();

  test('descargar, vender y reservar sin red, reiniciar, sincronizar sin duplicar', () async {
    // la unica caja de Equipetrol puede tenerla abierta la cajera demo: se cierra antes
    final cajera = await api.post('/auth/login', cuerpo: {
      'email': 'cajera.scz@fashionstore.bo',
      'password': 'demo1234',
    }) as Map<String, dynamic>;
    api.obtenerToken = () => cajera['access_token'] as String;
    api.obtenerEmpresa = () => 'fashionstore';
    try {
      await api.post('/caja/cerrar', cuerpo: {'monto_declarado': 0});
    } on Exception catch (_) {}

    final login = await api.post('/auth/login', cuerpo: {
      'email': 'admin@fashionstore.bo',
      'password': 'demo1234',
    }) as Map<String, dynamic>;
    final token = login['access_token'] as String;
    final usuario = login['usuario'] as Map<String, dynamic>;
    api.obtenerToken = () => token;
    api.obtenerEmpresa = () => usuario['empresa_slug'] as String?;

    // la venta offline necesita la caja abierta de quien la registra (si ya estaba, 409)
    final cajas = comoLista(await api.get('/caja/cajas'));
    for (final caja in cajas) {
      try {
        await api.post('/caja/abrir', cuerpo: {'caja_id': caja['id'], 'monto_inicial': 100});
        break;
      } on Exception catch (e) {
        // ignore: avoid_print
        print('caja ${caja['id']}: $e');
      }
    }

    final carpeta = await Directory.systemTemp.createTemp('fs_sync_vivo_');
    final ruta = '${carpeta.path}/local.db';
    final conexion = ConexionService(conectividad: _ConectividadFija());
    var base = BaseLocal(fabrica: databaseFactoryFfi, ruta: ruta);
    var sync = SincronizacionService(usuarioActual: () => usuario['id'] as String, conexion: conexion, base: base);

    // 1. descargar el paquete (con red)
    final paquete = await sync.descargarPaquete();
    expect(paquete.productos, isNotEmpty);
    expect(paquete.sesionCajaId, isNotNull, reason: 'el paquete trae la sesion de caja abierta');
    final variante = paquete.productos
        .expand((p) => p.variantes)
        .firstWhere((v) => v.disponible >= 2, orElse: () => throw StateError('sin stock para probar'));
    final antes = variante.disponible;
    expect(paquete.clientes, isNotEmpty);

    // 2. se corta la red: venta de contado y reserva quedan solo en el telefono
    conexion.enLinea = false;
    conexion.notifyListeners();
    final venta = await sync.registrarVenta([LineaNueva(variante.id, 1)], montoRecibido: 500);
    final manana = DateTime.now().add(const Duration(days: 1));
    final reserva = await sync.registrarReserva(
      [LineaNueva(variante.id, 1)],
      clienteEmail: paquete.clientes.first.email,
      fechaVisita: '${manana.year}-${manana.month.toString().padLeft(2, '0')}-${manana.day.toString().padLeft(2, '0')}',
      horaVisita: '11:00',
    );
    expect(sync.pendientes, 2);
    expect(sync.paquete!.variante(variante.id)!.disponible, antes - 2, reason: 'se descuenta localmente');

    // 3. "reiniciar la app": servicio y base nuevos sobre el mismo archivo
    sync.dispose();
    base = BaseLocal(fabrica: databaseFactoryFfi, ruta: ruta);
    sync = SincronizacionService(usuarioActual: () => usuario['id'] as String, conexion: conexion, base: base);
    await sync.cargarLocal();
    expect(sync.operaciones.map((o) => o.id).toSet(), {venta.id, reserva.id});
    expect(sync.operaciones.every((o) => o.estado == EstadoLocal.registrada), isTrue);

    // 4. vuelve la red: sincroniza y queda el resultado del servidor
    conexion.enLinea = true;
    await sync.sincronizar();
    final v = sync.operaciones.firstWhere((o) => o.id == venta.id);
    final r = sync.operaciones.firstWhere((o) => o.id == reserva.id);
    expect(v.estado, EstadoLocal.confirmada, reason: '${v.codigoMotivo} ${v.motivo}');
    expect(r.estado, EstadoLocal.confirmada, reason: '${r.codigoMotivo} ${r.motivo}');
    expect(v.numero, isNotNull);

    // 5. reenvio de una confirmada (p.ej. se perdio la respuesta): mismo resultado, sin duplicar
    await base.actualizarOperacion(venta.id, {'estado': 'ENVIADA'});
    await sync.cargarLocal();
    await sync.sincronizar();
    final v2 = sync.operaciones.firstWhere((o) => o.id == venta.id);
    expect(v2.estado, EstadoLocal.confirmada);
    expect(v2.duplicada, isTrue);
    expect(v2.numero, v.numero, reason: 'devuelve la misma venta, no una nueva');

    // 6. conflicto: mas unidades de las que tiene el servidor
    final conflicto = await sync.registrarVenta([LineaNueva(variante.id, 99)]);
    await sync.sincronizar();
    final c = sync.operaciones.firstWhere((o) => o.id == conflicto.id);
    expect(c.estado, isNot(EstadoLocal.confirmada));
    expect(c.codigoMotivo, isNotNull);
    // se reintenta y sigue igual: la operacion no se pierde
    await sync.resolver(conflicto.id, 'REINTENTAR');
    expect(sync.operaciones.any((o) => o.id == conflicto.id), isTrue);

    // la consulta al servidor coincide con lo local
    final servidor = await api.get('/sync/operaciones/${venta.id}') as Map<String, dynamic>;
    expect(servidor['estado'], 'CONFIRMADA');
    expect(aEntero(servidor['intentos']), greaterThanOrEqualTo(2));

    // limpieza: el conflicto se descarta desde el servidor si se puede (no lo deja abierto)
    sync.dispose();
    await carpeta.delete(recursive: true).catchError((_) => carpeta);
    // ignore: avoid_print
    print('venta ${v.numero} confirmada, reserva ${r.numero}, conflicto ${c.codigoMotivo}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

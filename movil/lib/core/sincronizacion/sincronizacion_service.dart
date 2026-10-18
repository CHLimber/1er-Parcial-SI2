import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api.dart';
import '../errores.dart';
import '../offline/base_local.dart';
import '../offline/conexion_service.dart';
import 'sincronizacion_models.dart';

const _lote = 50;
const _reintentoBase = Duration(seconds: 30);
const _reintentoMaximo = Duration(minutes: 10);
const _periodo = Duration(seconds: 60);

/// UUID v4 con el generador criptografico del sistema (RN10: lo genera el dispositivo).
String nuevoUuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

class LineaNueva {
  const LineaNueva(this.varianteId, this.cantidad);

  final String varianteId;
  final int cantidad;
}

/// Operacion offline del personal en el movil (Modulos C y D), espejo de
/// `SincronizacionService` de la web con SQLite en vez de IndexedDB: baja el paquete de la
/// sucursal (CU13), registra ventas de contado y reservas con un UUID propio (CU15/CU16), las
/// manda al volver la red (CU19) con reintentos y backoff, y guarda lo que contesto el servidor
/// (CU20). Las operaciones nunca se borran por enviarse (RN12): una ENVIADA cuya respuesta no
/// llego se reenvia con el mismo id y el servidor devuelve lo que ya habia hecho (RN11).
class SincronizacionService extends ChangeNotifier {
  SincronizacionService({
    required this.usuarioActual,
    required this.conexion,
    BaseLocal? base,
  }) : _base = base ?? baseLocal {
    conexion.addListener(_alCambiarConexion);
    _enLineaAntes = conexion.enLinea;
    _periodico = Timer.periodic(_periodo, (_) {
      if (conexion.enLinea && pendientes > 0) sincronizar();
    });
  }

  /// id del usuario logueado (las operaciones y el paquete son de el)
  final String? Function() usuarioActual;
  final ConexionService conexion;
  final BaseLocal _base;
  late bool _enLineaAntes;
  Timer? _periodico;
  Timer? _reintento;
  int _intentosFallidos = 0;
  Future<void>? _enCurso;
  bool _otraVuelta = false;

  PaqueteLocal? paquete;
  List<OperacionLocal> operaciones = const [];
  bool sincronizando = false;
  String? ultimoResultado;

  int get pendientes => operaciones.where((o) => o.estado.pendiente).length;
  int get enConflicto => operaciones.where((o) => o.estado == EstadoLocal.conflicto).length;

  void _alCambiarConexion() {
    // al volver la red se manda lo pendiente (el "evento de red" del CU19)
    if (conexion.enLinea && !_enLineaAntes) sincronizar();
    _enLineaAntes = conexion.enLinea;
  }

  /// Lee de SQLite lo del usuario logueado (paquete y operaciones). Sobrevive a reiniciar la app.
  Future<void> cargarLocal() async {
    final usuario = usuarioActual();
    if (usuario == null) {
      paquete = null;
      operaciones = const [];
      notifyListeners();
      return;
    }
    try {
      paquete = await _leerPaquete(usuario);
      operaciones = (await _base.operaciones(usuario)).map(OperacionLocal.desdeFila).toList();
    } catch (_) {
      // sin base local (tests): solo online
    }
    notifyListeners();
  }

  Future<PaqueteLocal?> _leerPaquete(String usuario) async {
    final guardado = await _base.leerPaquete(usuario);
    if (guardado == null) return null;
    final (sucursal, productos, variantes, clientes) = guardado;
    return PaqueteLocal(
      empresaId: sucursal['empresa_id']! as String,
      empresa: sucursal['empresa']! as String,
      sucursalId: sucursal['id']! as String,
      sucursal: sucursal['nombre']! as String,
      sesionCajaId: sucursal['sesion_caja_id'] as String?,
      ivaTasa: aDouble(sucursal['iva_tasa']),
      generadoEn: DateTime.parse(sucursal['generado_en']! as String),
      productos: [
        for (final p in productos)
          ProductoLocal(
            id: p['id']! as String,
            codigo: p['codigo']! as String,
            nombre: p['nombre']! as String,
            categoria: p['categoria']! as String,
            imagenUrl: p['imagen_url'] as String?,
            variantes: [
              for (final v in variantes.where((v) => v['producto_id'] == p['id']))
                VarianteLocal.desdeFila(v),
            ],
          ),
      ],
      clientes: [
        for (final c in clientes)
          ClienteLocal(
            nombre: c['nombre']! as String,
            email: c['email']! as String,
            telefono: c['telefono'] as String?,
          ),
      ],
    );
  }

  /// CU13: baja (o refresca) el paquete de la sucursal. Necesita red.
  Future<PaqueteLocal> descargarPaquete({String? sucursalId}) async {
    final usuario = _exigirUsuario();
    final datos = await api.get('/sync/catalogo', query: {'sucursal_id': sucursalId})
        as Map<String, dynamic>;
    await _base.guardarPaquete(datos, usuario);
    // lo vendido offline que todavia no se confirmo ya no esta en el stock del servidor: se
    // vuelve a descontar del paquete nuevo para no ofrecer dos veces la misma prenda
    final comprometido = <String, int>{};
    for (final o in operaciones.where((o) => o.estado.pendiente)) {
      for (final l in o.lineas) {
        comprometido[l.varianteId] = (comprometido[l.varianteId] ?? 0) + l.cantidad;
      }
    }
    if (comprometido.isNotEmpty) await _base.descontarExistencias(comprometido);
    paquete = await _leerPaquete(usuario);
    notifyListeners();
    return paquete!;
  }

  /// CU16: venta de contado registrada localmente (aunque haya red, pasa por la misma cola).
  Future<OperacionLocal> registrarVenta(
    List<LineaNueva> lineas, {
    double? montoRecibido,
    String? clienteEmail,
  }) async {
    final p = _exigirPaquete();
    final total = totalConIva(
      lineas.map((l) => (p.variante(l.varianteId)!.precio, l.cantidad)),
      p.ivaTasa,
    );
    return _guardarNueva(
      p,
      tipo: 'VENTA',
      lineas: lineas,
      total: total,
      descripcion: 'Venta: ${_resumen(p, lineas)}',
      extra: {
        'metodo_pago': 'EFECTIVO',
        'monto_recibido': montoRecibido,
        'sesion_caja_id': p.sesionCajaId,
        'cliente_email': clienteEmail,
      },
    );
  }

  /// CU15: reserva registrada localmente para una clienta de la cartera.
  Future<OperacionLocal> registrarReserva(
    List<LineaNueva> lineas, {
    required String clienteEmail,
    required String fechaVisita,
    required String horaVisita,
    String? observaciones,
  }) async {
    final p = _exigirPaquete();
    return _guardarNueva(
      p,
      tipo: 'RESERVA',
      lineas: lineas,
      total: 0,
      descripcion: 'Reserva para $clienteEmail: ${_resumen(p, lineas)}',
      extra: {
        'cliente_email': clienteEmail,
        'fecha_visita': fechaVisita,
        'hora_visita': horaVisita,
        'observaciones': observaciones,
      },
    );
  }

  /// CU19: manda lo pendiente, en orden de registro. Lo disparan el boton, la vuelta de la
  /// red y un temporizador; ante un fallo de red se reintenta con espera creciente.
  Future<void> sincronizar() {
    // si ya hay una vuelta en curso se espera esa misma; lo registrado mientras tanto sale en
    // una vuelta mas, apenas termine
    final enCurso = _enCurso;
    if (enCurso != null) {
      _otraVuelta = true;
      return enCurso;
    }
    final vuelta = _sincronizar().whenComplete(() {
      _enCurso = null;
      if (_otraVuelta) {
        _otraVuelta = false;
        sincronizar();
      }
    });
    _enCurso = vuelta;
    return vuelta;
  }

  Future<void> _sincronizar() async {
    if (!conexion.enLinea) return;
    final porEnviar = operaciones.where((o) => o.estado.pendiente).toList()
      ..sort((a, b) => a.registradaEn.compareTo(b.registradaEn));
    if (porEnviar.isEmpty) return;
    sincronizando = true;
    notifyListeners();
    var confirmadas = 0;
    var rechazadas = 0;
    var conflictos = 0;
    final respondidas = <String>{};
    try {
      for (var i = 0; i < porEnviar.length; i += _lote) {
        final lote = porEnviar.sublist(i, min(i + _lote, porEnviar.length));
        final ahora = DateTime.now().toIso8601String();
        for (final o in lote) {
          await _base.actualizarOperacion(o.id, {
            'estado': 'ENVIADA',
            'intentos_envio': o.intentosEnvio + 1,
            'ultimo_envio': ahora,
          });
        }
        final respuesta = await api.post(
          '/sync/operaciones',
          cuerpo: {'operaciones': lote.map((o) => o.aJson()).toList()},
        ) as Map<String, dynamic>;
        for (final r in comoLista(respuesta['resultados'])) {
          await _aplicarRespuesta(r);
          respondidas.add(r['id'] as String);
        }
        confirmadas += aEntero(respuesta['confirmadas']);
        rechazadas += aEntero(respuesta['rechazadas']);
        conflictos += aEntero(respuesta['en_conflicto']);
      }
      _intentosFallidos = 0;
      ultimoResultado = 'Sincronizacion: $confirmadas confirmada(s), $rechazadas rechazada(s), '
          '$conflictos en conflicto.';
    } on ApiException catch (e) {
      // la operacion queda ENVIADA (sin respuesta) y se reintenta con el mismo id
      final mensaje = e.statusCode == null
          ? 'Sin conexion con el servidor: se reintenta solo.'
          : e.statusCode == 401
              ? 'La sesion expiro: inicia sesion para sincronizar.'
              : 'El servidor respondio ${e.statusCode}: se reintenta mas tarde.';
      for (final o in porEnviar.where((o) => !respondidas.contains(o.id))) {
        await _base.actualizarOperacion(o.id, {'error_red': mensaje});
      }
      ultimoResultado = mensaje;
      _programarReintento();
    } finally {
      sincronizando = false;
      await cargarLocal();
    }
  }

  /// CU21: reintentar / aceptar el precio actual / descartar una operacion en conflicto.
  Future<void> resolver(String id, String accion, {String? nota}) async {
    final r = await api.post('/sync/operaciones/$id/resolver', cuerpo: {'accion': accion, 'nota': nota});
    await _aplicarRespuesta(r as Map<String, dynamic>);
    await cargarLocal();
  }

  /// CU20: vuelve a preguntar al servidor como quedo (p.ej. si el encargado lo resolvio).
  Future<void> refrescar(String id) async {
    final r = await api.get('/sync/operaciones/$id');
    await _aplicarRespuesta(r as Map<String, dynamic>);
    await cargarLocal();
  }

  /// Saca del dispositivo las operaciones ya cerradas. Las pendientes y en conflicto quedan.
  Future<int> archivarCerradas() async {
    final n = await _base.archivarCerradas(_exigirUsuario());
    await cargarLocal();
    return n;
  }

  // -------------------------------------------------------------------------------------------

  String _exigirUsuario() {
    final usuario = usuarioActual();
    if (usuario == null) throw ApiException('Inicia sesion para operar sin conexion.');
    return usuario;
  }

  PaqueteLocal _exigirPaquete() {
    final p = paquete;
    if (p == null) {
      throw ApiException('Descarga el catalogo de la sucursal antes de operar sin conexion.');
    }
    return p;
  }

  String _resumen(PaqueteLocal p, List<LineaNueva> lineas) =>
      lineas.map((l) => '${l.cantidad}x ${p.descripcionDe(l.varianteId)}').join(', ');

  Future<OperacionLocal> _guardarNueva(
    PaqueteLocal p, {
    required String tipo,
    required List<LineaNueva> lineas,
    required double total,
    required String descripcion,
    required Map<String, Object?> extra,
  }) async {
    final id = nuevoUuid();
    await _base.guardarOperacion(
      {
        'id': id,
        'tipo': tipo,
        'empresa_id': p.empresaId,
        'sucursal_id': p.sucursalId,
        'usuario_id': _exigirUsuario(),
        'registrada_en': DateTime.now().toUtc().toIso8601String(),
        'estado': 'REGISTRADA',
        'descripcion': descripcion,
        'total': total,
        ...extra,
      },
      [
        for (final l in lineas)
          {
            'variante_id': l.varianteId,
            'cantidad': l.cantidad,
            'precio_unitario': p.variante(l.varianteId)!.precio,
            'descripcion': p.descripcionDe(l.varianteId),
          },
      ],
    );
    // la existencia conocida baja en el dispositivo: no se ofrece de nuevo lo ya vendido
    await _base.descontarExistencias({for (final l in lineas) l.varianteId: l.cantidad});
    await cargarLocal();
    unawaited(sincronizar());
    return operaciones.firstWhere((o) => o.id == id);
  }

  Future<void> _aplicarRespuesta(Map<String, dynamic> r) async {
    final id = r['id'] as String;
    if (!operaciones.any((o) => o.id == id)) return;
    await _base.guardarResultado(id, {
      'estado': r['estado'],
      'codigo_motivo': r['codigo_motivo'],
      'motivo': r['motivo'],
      'resultado': r['resultado'] == null ? null : jsonEncode(r['resultado']),
      'duplicada': r['duplicada'] == true ? 1 : 0,
      'intentos': aEntero(r['intentos']),
      'recibida_en': r['recibida_en'],
      'resuelta_en': r['resuelta_en'],
      'resolucion': r['resolucion'],
      'actualizado_en': DateTime.now().toIso8601String(),
    });
  }

  void _programarReintento() {
    _reintento?.cancel();
    final espera = _reintentoBase * pow(2, _intentosFallidos).toInt();
    _intentosFallidos++;
    _reintento = Timer(espera > _reintentoMaximo ? _reintentoMaximo : espera, sincronizar);
  }

  @override
  void dispose() {
    conexion.removeListener(_alCambiarConexion);
    _periodico?.cancel();
    _reintento?.cancel();
    super.dispose();
  }
}

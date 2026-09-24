import '../api.dart';

/// Espejo de `backend/app/modules/inventario/schemas.py` (PENDIENTES.txt 2.6, ajustes
/// manuales de stock). Cada modulo mantiene su propio schema en vez de importar el de
/// recepciones (mismo criterio que backend y frontend, ver CLAUDE.md).
class VarianteBuscadaOut {
  VarianteBuscadaOut({
    required this.id,
    required this.sku,
    required this.producto,
    required this.talla,
    required this.color,
    required this.codigoHex,
    required this.sucursalId,
    required this.sucursal,
    required this.cantidadFisica,
    required this.cantidadReservada,
    required this.disponible,
  });

  final String id;
  final String sku;
  final String producto;
  final String talla;
  final String color;
  final String codigoHex;
  final String sucursalId;
  final String sucursal;
  final int cantidadFisica;
  final int cantidadReservada;
  final int disponible;

  factory VarianteBuscadaOut.desdeJson(Map<String, dynamic> j) => VarianteBuscadaOut(
        id: j['id'] as String,
        sku: j['sku'] as String,
        producto: j['producto'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        codigoHex: j['codigo_hex'] as String,
        sucursalId: j['sucursal_id'] as String,
        sucursal: j['sucursal'] as String,
        cantidadFisica: aEntero(j['cantidad_fisica']),
        cantidadReservada: aEntero(j['cantidad_reservada']),
        disponible: aEntero(j['disponible']),
      );
}

/// saldo_anterior/saldo_nuevo son el DISPONIBLE (fisico - reservado) para todos los tipos
/// salvo AJUSTE, donde son cantidad_fisica cruda (fn_mover_inventario, db/02_logica.sql).
class MovimientoKardexOut {
  MovimientoKardexOut({
    required this.id,
    required this.tipo,
    required this.cantidad,
    required this.saldoAnterior,
    required this.saldoNuevo,
    required this.motivo,
    required this.documentoTipo,
    required this.documentoId,
    required this.usuario,
    required this.fecha,
  });

  final int id;
  final String tipo;
  final int cantidad;
  final int saldoAnterior;
  final int saldoNuevo;
  final String? motivo;
  final String? documentoTipo;
  final String? documentoId;
  final String? usuario;
  final DateTime fecha;

  factory MovimientoKardexOut.desdeJson(Map<String, dynamic> j) => MovimientoKardexOut(
        id: aEntero(j['id']),
        tipo: j['tipo'] as String,
        cantidad: aEntero(j['cantidad']),
        saldoAnterior: aEntero(j['saldo_anterior']),
        saldoNuevo: aEntero(j['saldo_nuevo']),
        motivo: j['motivo'] as String?,
        documentoTipo: j['documento_tipo'] as String?,
        documentoId: j['documento_id'] as String?,
        usuario: j['usuario'] as String?,
        fecha: DateTime.parse(j['fecha'] as String),
      );
}

class AjusteOut {
  AjusteOut({
    required this.movimientoId,
    required this.sucursalId,
    required this.varianteId,
    required this.saldoAnterior,
    required this.saldoNuevo,
    required this.motivo,
    required this.fecha,
  });

  final int movimientoId;
  final String sucursalId;
  final String varianteId;
  final int saldoAnterior;
  final int saldoNuevo;
  final String motivo;
  final DateTime fecha;

  factory AjusteOut.desdeJson(Map<String, dynamic> j) => AjusteOut(
        movimientoId: aEntero(j['movimiento_id']),
        sucursalId: j['sucursal_id'] as String,
        varianteId: j['variante_id'] as String,
        saldoAnterior: aEntero(j['saldo_anterior']),
        saldoNuevo: aEntero(j['saldo_nuevo']),
        motivo: j['motivo'] as String,
        fecha: DateTime.parse(j['fecha'] as String),
      );
}

/// Ajustes manuales de stock (PENDIENTES.txt 2.6): buscador + kardex + registro de ajuste.
/// El backend es el unico que escribe cantidad_fisica, siempre via fn_mover_inventario
/// (db/02_logica.sql) -- este servicio nunca calcula stock, solo lo pide y lo muestra.
class InventarioService {
  Future<List<VarianteBuscadaOut>> buscarVariantes(String q, {String? sucursalId}) async {
    final respuesta = await api.get('/inventario/variantes', query: {
      'q': q,
      'sucursal_id': sucursalId,
    });
    return comoLista(respuesta).map(VarianteBuscadaOut.desdeJson).toList();
  }

  Future<List<MovimientoKardexOut>> kardex(
    String varianteId, {
    required String sucursalId,
    int limite = 50,
  }) async {
    final respuesta = await api.get('/inventario/$varianteId/kardex', query: {
      'sucursal_id': sucursalId,
      'limite': limite,
    });
    return comoLista(respuesta).map(MovimientoKardexOut.desdeJson).toList();
  }

  /// `cantidadFisicaNueva` es el saldo ABSOLUTO nuevo (no un delta) y tiene que ser > 0:
  /// fn_mover_inventario no permite dejar una variante en 0 unidades por esta via todavia.
  Future<AjusteOut> ajustar({
    required String sucursalId,
    required String varianteId,
    required int cantidadFisicaNueva,
    required String motivo,
  }) async {
    final respuesta = await api.post('/inventario/ajustes', cuerpo: {
      'sucursal_id': sucursalId,
      'variante_id': varianteId,
      'cantidad_fisica_nueva': cantidadFisicaNueva,
      'motivo': motivo,
    });
    return AjusteOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final inventarioService = InventarioService();

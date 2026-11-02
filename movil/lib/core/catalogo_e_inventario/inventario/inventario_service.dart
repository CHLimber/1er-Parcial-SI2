import '../../api.dart';

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
    this.stockMinimo = 0,
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

  /// Umbral de reposicion de la prenda en la sucursal (0 = sin umbral).
  final int stockMinimo;

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
        stockMinimo: aEntero(j['stock_minimo']),
      );
}

/// Indicadores de una sucursal para la cabecera de la pantalla (GET /inventario/resumen).
class ResumenInventarioOut {
  ResumenInventarioOut({
    required this.sucursal,
    required this.variantes,
    required this.unidadesFisicas,
    required this.unidadesReservadas,
    required this.unidadesDisponibles,
    required this.agotadas,
    required this.stockBajo,
  });

  final String sucursal;
  final int variantes;
  final int unidadesFisicas;
  final int unidadesReservadas;
  final int unidadesDisponibles;
  final int agotadas;
  final int stockBajo;

  factory ResumenInventarioOut.desdeJson(Map<String, dynamic> j) => ResumenInventarioOut(
        sucursal: j['sucursal'] as String,
        variantes: aEntero(j['variantes']),
        unidadesFisicas: aEntero(j['unidades_fisicas']),
        unidadesReservadas: aEntero(j['unidades_reservadas']),
        unidadesDisponibles: aEntero(j['unidades_disponibles']),
        agotadas: aEntero(j['agotadas']),
        stockBajo: aEntero(j['stock_bajo']),
      );
}

/// Filtro rapido del listado: las que piden reposicion o las que no tienen nada disponible.
enum AlertaInventario { bajo, agotadas }

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
  /// Sin texto lista las prendas con menos disponible primero; `alerta` filtra las que piden reposicion.
  Future<List<VarianteBuscadaOut>> buscarVariantes(
    String q, {
    String? sucursalId,
    AlertaInventario? alerta,
  }) async {
    final respuesta = await api.get('/inventario/variantes', query: {
      'q': q,
      'sucursal_id': sucursalId,
      'alerta': alerta?.name,
    });
    return comoLista(respuesta).map(VarianteBuscadaOut.desdeJson).toList();
  }

  Future<ResumenInventarioOut> resumen({String? sucursalId}) async => ResumenInventarioOut.desdeJson(
      await api.get('/inventario/resumen', query: {'sucursal_id': sucursalId}) as Map<String, dynamic>);

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

  /// `cantidadFisicaNueva` es el saldo ABSOLUTO nuevo (no un delta) y puede ser 0 (se perdio o
  /// se danio la ultima unidad). No puede quedar por debajo de lo reservado: el backend da 409.
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

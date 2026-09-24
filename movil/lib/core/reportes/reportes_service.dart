import '../api.dart';
import 'reportes_models.dart';

/// CU15 - Consultar Reportes e Indicadores, espejo movil de
/// `frontend/src/app/core/reportes/reportes.service.ts`. Un ENCARGADO solo ve su propia
/// sucursal (el backend lo resuelve solo); un ADMIN puede pedir cualquiera o la cadena
/// completa (sucursalId nulo). Sin capa de repositorio: cada metodo pega directo al
/// endpoint que le corresponde.
class ReportesService {
  String _soloFecha(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';

  // --- Dinamicos: aceptan fecha/sucursal/canal/categoria/entrega ------------------------

  Future<IndicadoresOut> obtenerIndicadores({
    DateTime? desde,
    DateTime? hasta,
    String? sucursalId,
    String? categoriaId,
    String? canal,
    String? entrega,
  }) async {
    final respuesta = await api.get('/reportes/indicadores', query: {
      'desde': desde == null ? null : _soloFecha(desde),
      'hasta': hasta == null ? null : _soloFecha(hasta),
      'sucursal_id': sucursalId,
      'categoria_id': categoriaId,
      'canal': canal,
      'entrega': entrega,
    });
    return IndicadoresOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<List<VentaDiariaOut>> listarVentasDiarias({
    DateTime? desde,
    DateTime? hasta,
    String? sucursalId,
    String? categoriaId,
    String? canal,
    String? entrega,
  }) async {
    final respuesta = await api.get('/reportes/ventas-diarias', query: {
      'desde': desde == null ? null : _soloFecha(desde),
      'hasta': hasta == null ? null : _soloFecha(hasta),
      'sucursal_id': sucursalId,
      'categoria_id': categoriaId,
      'canal': canal,
      'entrega': entrega,
    });
    return comoLista(respuesta).map(VentaDiariaOut.desdeJson).toList();
  }

  Future<List<VentaPorSucursalOut>> listarVentasPorSucursal({
    DateTime? desde,
    DateTime? hasta,
    String? sucursalId,
    String? categoriaId,
    String? canal,
    String? entrega,
  }) async {
    final respuesta = await api.get('/reportes/ventas-por-sucursal', query: {
      'desde': desde == null ? null : _soloFecha(desde),
      'hasta': hasta == null ? null : _soloFecha(hasta),
      'sucursal_id': sucursalId,
      'categoria_id': categoriaId,
      'canal': canal,
      'entrega': entrega,
    });
    return comoLista(respuesta).map(VentaPorSucursalOut.desdeJson).toList();
  }

  Future<List<ProductoRankingOut>> listarTopProductos({
    DateTime? desde,
    DateTime? hasta,
    String? sucursalId,
    String? categoriaId,
    String? canal,
    String? entrega,
    int limite = 10,
  }) async {
    final respuesta = await api.get('/reportes/top-productos', query: {
      'desde': desde == null ? null : _soloFecha(desde),
      'hasta': hasta == null ? null : _soloFecha(hasta),
      'sucursal_id': sucursalId,
      'categoria_id': categoriaId,
      'canal': canal,
      'entrega': entrega,
      'limite': limite,
    });
    return comoLista(respuesta).map(ProductoRankingOut.desdeJson).toList();
  }

  // --- Estaticos: foto del estado actual, sin filtro de fecha ---------------------------

  Future<List<StockSucursalOut>> listarStockPorSucursal({String? sucursalId}) async {
    final respuesta =
        await api.get('/reportes/stock-por-sucursal', query: {'sucursal_id': sucursalId});
    return comoLista(respuesta).map(StockSucursalOut.desdeJson).toList();
  }

  Future<List<ReservaEstadoOut>> listarReservasPorEstado({String? sucursalId}) async {
    final respuesta =
        await api.get('/reportes/reservas-por-estado', query: {'sucursal_id': sucursalId});
    return comoLista(respuesta).map(ReservaEstadoOut.desdeJson).toList();
  }

  Future<List<EnvioEstadoOut>> listarEnviosPorEstado({String? sucursalId}) async {
    final respuesta =
        await api.get('/reportes/envios-por-estado', query: {'sucursal_id': sucursalId});
    return comoLista(respuesta).map(EnvioEstadoOut.desdeJson).toList();
  }

  Future<List<ProductoSinMovimientoOut>> listarProductosSinMovimiento({
    String? sucursalId,
    int limite = 50,
  }) async {
    final respuesta = await api.get(
      '/reportes/productos-sin-movimiento',
      query: {'sucursal_id': sucursalId, 'limite': limite},
    );
    return comoLista(respuesta).map(ProductoSinMovimientoOut.desdeJson).toList();
  }

  Future<List<ClienteRankingOut>> listarTopClientes({
    String? sucursalId,
    int limite = 10,
  }) async {
    final respuesta = await api.get(
      '/reportes/top-clientes',
      query: {'sucursal_id': sucursalId, 'limite': limite},
    );
    return comoLista(respuesta).map(ClienteRankingOut.desdeJson).toList();
  }

  Future<List<CajaOcupacionOut>> listarOcupacionCajas({String? sucursalId}) async {
    final respuesta =
        await api.get('/reportes/ocupacion-cajas', query: {'sucursal_id': sucursalId});
    return comoLista(respuesta).map(CajaOcupacionOut.desdeJson).toList();
  }

  Future<List<RecepcionPendienteProveedorOut>> listarRecepcionesPendientes({
    String? sucursalId,
  }) async {
    final respuesta =
        await api.get('/reportes/recepciones-pendientes', query: {'sucursal_id': sucursalId});
    return comoLista(respuesta).map(RecepcionPendienteProveedorOut.desdeJson).toList();
  }

  /// PENDIENTES 2.19.5: consolidado de existencias, paginado.
  Future<ExistenciasPaginadoOut> listarExistencias({
    String? sucursalId,
    String? categoriaId,
    String? busqueda,
    String? situacion,
    int pagina = 1,
    int tamanioPagina = 50,
  }) async {
    final respuesta = await api.get('/reportes/existencias', query: {
      'sucursal_id': sucursalId,
      'categoria_id': categoriaId,
      'busqueda': (busqueda?.isEmpty ?? true) ? null : busqueda,
      'situacion': situacion,
      'pagina': pagina,
      'tamanio_pagina': tamanioPagina,
    });
    return ExistenciasPaginadoOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  // --- IA / VOZ: mismo patron de tool-use que CU18, sin persistencia --------------------

  Future<ConsultaIaOut> consultarIa(List<MensajeReporte> mensajes) async {
    final respuesta = await api.post(
      '/reportes/consulta-ia',
      cuerpo: {'mensajes': mensajes.map((m) => m.aJson()).toList()},
    );
    return ConsultaIaOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final reportesService = ReportesService();

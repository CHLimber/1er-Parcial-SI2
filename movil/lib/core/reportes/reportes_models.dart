import '../api.dart';

/// CU15 - Consultar Reportes e Indicadores. Espejo manual de
/// `backend/app/modules/reportes/schemas.py` (mismo criterio que el resto del proyecto:
/// si el schema del backend cambia hay que actualizar esto a mano). Permiso unico
/// `reportes.leer`, sembrado para ADMIN y ENCARGADO.
const permisoReportes = 'reportes.leer';

/// Los campos `envios*`/`costo_envio_total` (CU20) pueden no estar todavia en algunas
/// respuestas si el backend no se redesplego -- se leen con los mismos parseos
/// `aEntero`/`aDouble` de siempre, que devuelven 0 ante un valor ausente.
class IndicadoresOut {
  IndicadoresOut({
    required this.desde,
    required this.hasta,
    required this.ventasCantidad,
    required this.ventasMonto,
    required this.ticketPromedio,
    required this.reservasCreadas,
    required this.reservasConvertidas,
    required this.tasaConversionReservas,
    required this.variantesStockBajo,
    required this.variantesAgotadas,
    required this.enviosCantidad,
    required this.enviosMonto,
  });

  final String desde;
  final String hasta;
  final int ventasCantidad;
  final double ventasMonto;
  final double ticketPromedio;
  final int reservasCreadas;
  final int reservasConvertidas;
  final double tasaConversionReservas;
  final int variantesStockBajo;
  final int variantesAgotadas;
  final int enviosCantidad;
  final double enviosMonto;

  factory IndicadoresOut.desdeJson(Map<String, dynamic> j) => IndicadoresOut(
        desde: j['desde'] as String,
        hasta: j['hasta'] as String,
        ventasCantidad: aEntero(j['ventas_cantidad']),
        ventasMonto: aDouble(j['ventas_monto']),
        ticketPromedio: aDouble(j['ticket_promedio']),
        reservasCreadas: aEntero(j['reservas_creadas']),
        reservasConvertidas: aEntero(j['reservas_convertidas']),
        tasaConversionReservas: aDouble(j['tasa_conversion_reservas']),
        variantesStockBajo: aEntero(j['variantes_stock_bajo']),
        variantesAgotadas: aEntero(j['variantes_agotadas']),
        enviosCantidad: aEntero(j['envios_cantidad']),
        enviosMonto: aDouble(j['envios_monto']),
      );
}

class VentaDiariaOut {
  VentaDiariaOut({
    required this.dia,
    required this.sucursalId,
    required this.sucursal,
    required this.canal,
    required this.cantidadVentas,
    required this.montoTotal,
    required this.ticketPromedio,
  });

  final String dia;
  final String sucursalId;
  final String sucursal;
  final String canal;
  final int cantidadVentas;
  final double montoTotal;
  final double ticketPromedio;

  factory VentaDiariaOut.desdeJson(Map<String, dynamic> j) => VentaDiariaOut(
        dia: j['dia'] as String,
        sucursalId: j['sucursal_id'] as String,
        sucursal: j['sucursal'] as String,
        canal: j['canal'] as String,
        cantidadVentas: aEntero(j['cantidad_ventas']),
        montoTotal: aDouble(j['monto_total']),
        ticketPromedio: aDouble(j['ticket_promedio']),
      );
}

class VentaPorSucursalOut {
  VentaPorSucursalOut({
    required this.sucursalId,
    required this.sucursal,
    required this.cantidadVentas,
    required this.montoTotal,
    required this.ticketPromedio,
    required this.costoEnvioTotal,
  });

  final String sucursalId;
  final String sucursal;
  final int cantidadVentas;
  final double montoTotal;
  final double ticketPromedio;
  final double costoEnvioTotal;

  factory VentaPorSucursalOut.desdeJson(Map<String, dynamic> j) => VentaPorSucursalOut(
        sucursalId: j['sucursal_id'] as String,
        sucursal: j['sucursal'] as String,
        cantidadVentas: aEntero(j['cantidad_ventas']),
        montoTotal: aDouble(j['monto_total']),
        ticketPromedio: aDouble(j['ticket_promedio']),
        costoEnvioTotal: aDouble(j['costo_envio_total']),
      );
}

class ProductoRankingOut {
  ProductoRankingOut({
    required this.productoId,
    required this.producto,
    required this.unidadesVendidas,
    required this.montoVendido,
  });

  final String productoId;
  final String producto;
  final int unidadesVendidas;
  final double montoVendido;

  factory ProductoRankingOut.desdeJson(Map<String, dynamic> j) => ProductoRankingOut(
        productoId: j['producto_id'] as String,
        producto: j['producto'] as String,
        unidadesVendidas: aEntero(j['unidades_vendidas']),
        montoVendido: aDouble(j['monto_vendido']),
      );
}

class StockSucursalOut {
  StockSucursalOut({
    required this.sucursalId,
    required this.sucursal,
    required this.totalFisico,
    required this.totalReservado,
    required this.totalDisponible,
    required this.variantesAgotadas,
    required this.variantesStockBajo,
  });

  final String sucursalId;
  final String sucursal;
  final int totalFisico;
  final int totalReservado;
  final int totalDisponible;
  final int variantesAgotadas;
  final int variantesStockBajo;

  factory StockSucursalOut.desdeJson(Map<String, dynamic> j) => StockSucursalOut(
        sucursalId: j['sucursal_id'] as String,
        sucursal: j['sucursal'] as String,
        totalFisico: aEntero(j['total_fisico']),
        totalReservado: aEntero(j['total_reservado']),
        totalDisponible: aEntero(j['total_disponible']),
        variantesAgotadas: aEntero(j['variantes_agotadas']),
        variantesStockBajo: aEntero(j['variantes_stock_bajo']),
      );
}

class ReservaEstadoOut {
  ReservaEstadoOut({required this.estado, required this.cantidad});

  final String estado;
  final int cantidad;

  factory ReservaEstadoOut.desdeJson(Map<String, dynamic> j) =>
      ReservaEstadoOut(estado: j['estado'] as String, cantidad: aEntero(j['cantidad']));
}

class EnvioEstadoOut {
  EnvioEstadoOut({required this.estado, required this.cantidad});

  final String estado;
  final int cantidad;

  factory EnvioEstadoOut.desdeJson(Map<String, dynamic> j) =>
      EnvioEstadoOut(estado: j['estado'] as String, cantidad: aEntero(j['cantidad']));
}

class ProductoSinMovimientoOut {
  ProductoSinMovimientoOut({
    required this.varianteId,
    required this.producto,
    required this.talla,
    required this.color,
    required this.sucursalId,
    required this.sucursal,
    required this.cantidadFisica,
  });

  final String varianteId;
  final String producto;
  final String talla;
  final String color;
  final String sucursalId;
  final String sucursal;
  final int cantidadFisica;

  factory ProductoSinMovimientoOut.desdeJson(Map<String, dynamic> j) => ProductoSinMovimientoOut(
        varianteId: j['variante_id'] as String,
        producto: j['producto'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        sucursalId: j['sucursal_id'] as String,
        sucursal: j['sucursal'] as String,
        cantidadFisica: aEntero(j['cantidad_fisica']),
      );
}

class ClienteRankingOut {
  ClienteRankingOut({
    required this.usuarioId,
    required this.cliente,
    required this.email,
    required this.cantidadCompras,
    required this.montoTotal,
  });

  final String usuarioId;
  final String cliente;
  final String email;
  final int cantidadCompras;
  final double montoTotal;

  factory ClienteRankingOut.desdeJson(Map<String, dynamic> j) => ClienteRankingOut(
        usuarioId: j['usuario_id'] as String,
        cliente: j['cliente'] as String,
        email: j['email'] as String,
        cantidadCompras: aEntero(j['cantidad_compras']),
        montoTotal: aDouble(j['monto_total']),
      );
}

class CajaOcupacionOut {
  CajaOcupacionOut({
    required this.sucursalId,
    required this.sucursal,
    required this.totalCajas,
    required this.cajasAbiertas,
  });

  final String sucursalId;
  final String sucursal;
  final int totalCajas;
  final int cajasAbiertas;

  factory CajaOcupacionOut.desdeJson(Map<String, dynamic> j) => CajaOcupacionOut(
        sucursalId: j['sucursal_id'] as String,
        sucursal: j['sucursal'] as String,
        totalCajas: aEntero(j['total_cajas']),
        cajasAbiertas: aEntero(j['cajas_abiertas']),
      );
}

class RecepcionPendienteProveedorOut {
  RecepcionPendienteProveedorOut({
    required this.proveedorId,
    required this.proveedor,
    required this.cantidad,
    required this.montoTotal,
  });

  final String proveedorId;
  final String proveedor;
  final int cantidad;
  final double montoTotal;

  factory RecepcionPendienteProveedorOut.desdeJson(Map<String, dynamic> j) =>
      RecepcionPendienteProveedorOut(
        proveedorId: j['proveedor_id'] as String,
        proveedor: j['proveedor'] as String,
        cantidad: aEntero(j['cantidad']),
        montoTotal: aDouble(j['monto_total']),
      );
}

/// PENDIENTES 2.19.5: una fila de `v_existencias_consolidadas` (variante x sucursal).
class ExistenciaOut {
  ExistenciaOut({
    required this.productoId,
    required this.producto,
    required this.categoria,
    required this.varianteId,
    required this.sku,
    required this.talla,
    required this.color,
    required this.sucursalId,
    required this.sucursal,
    required this.cantidadFisica,
    required this.cantidadReservada,
    required this.disponible,
    required this.stockMinimo,
    required this.vendidas,
    required this.proximasAIngresar,
    required this.situacion,
  });

  final String productoId;
  final String producto;
  final String categoria;
  final String varianteId;
  final String sku;
  final String talla;
  final String color;
  final String sucursalId;
  final String sucursal;
  final int cantidadFisica;
  final int cantidadReservada;
  final int disponible;
  final int stockMinimo;
  final int vendidas;
  final int proximasAIngresar;
  final String situacion; // DISPONIBLE | RESERVADA | PROXIMA_A_INGRESAR | AGOTADA

  factory ExistenciaOut.desdeJson(Map<String, dynamic> j) => ExistenciaOut(
        productoId: j['producto_id'] as String,
        producto: j['producto'] as String,
        categoria: j['categoria'] as String,
        varianteId: j['variante_id'] as String,
        sku: j['sku'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        sucursalId: j['sucursal_id'] as String,
        sucursal: j['sucursal'] as String,
        cantidadFisica: aEntero(j['cantidad_fisica']),
        cantidadReservada: aEntero(j['cantidad_reservada']),
        disponible: aEntero(j['disponible']),
        stockMinimo: aEntero(j['stock_minimo']),
        vendidas: aEntero(j['vendidas']),
        proximasAIngresar: aEntero(j['proximas_a_ingresar']),
        situacion: j['situacion'] as String,
      );
}

class ResumenExistenciasOut {
  ResumenExistenciasOut({
    required this.variantesTotal,
    required this.variantesDisponibles,
    required this.variantesReservadas,
    required this.variantesProximasAIngresar,
    required this.variantesAgotadas,
    required this.unidadesFisicas,
    required this.unidadesReservadas,
    required this.unidadesDisponibles,
    required this.unidadesVendidas,
    required this.unidadesPorIngresar,
  });

  final int variantesTotal;
  final int variantesDisponibles;
  final int variantesReservadas;
  final int variantesProximasAIngresar;
  final int variantesAgotadas;
  final int unidadesFisicas;
  final int unidadesReservadas;
  final int unidadesDisponibles;
  final int unidadesVendidas;
  final int unidadesPorIngresar;

  factory ResumenExistenciasOut.desdeJson(Map<String, dynamic> j) => ResumenExistenciasOut(
        variantesTotal: aEntero(j['variantes_total']),
        variantesDisponibles: aEntero(j['variantes_disponibles']),
        variantesReservadas: aEntero(j['variantes_reservadas']),
        variantesProximasAIngresar: aEntero(j['variantes_proximas_a_ingresar']),
        variantesAgotadas: aEntero(j['variantes_agotadas']),
        unidadesFisicas: aEntero(j['unidades_fisicas']),
        unidadesReservadas: aEntero(j['unidades_reservadas']),
        unidadesDisponibles: aEntero(j['unidades_disponibles']),
        unidadesVendidas: aEntero(j['unidades_vendidas']),
        unidadesPorIngresar: aEntero(j['unidades_por_ingresar']),
      );
}

class ExistenciasPaginadoOut {
  ExistenciasPaginadoOut({
    required this.total,
    required this.pagina,
    required this.tamanioPagina,
    required this.resumen,
    required this.items,
  });

  final int total;
  final int pagina;
  final int tamanioPagina;
  final ResumenExistenciasOut resumen;
  final List<ExistenciaOut> items;

  factory ExistenciasPaginadoOut.desdeJson(Map<String, dynamic> j) => ExistenciasPaginadoOut(
        total: aEntero(j['total']),
        pagina: aEntero(j['pagina']),
        tamanioPagina: aEntero(j['tamanio_pagina']),
        resumen: ResumenExistenciasOut.desdeJson(j['resumen'] as Map<String, dynamic>),
        items: comoLista(j['items']).map(ExistenciaOut.desdeJson).toList(),
      );
}

/// Espejo de `asistente_models.dart::MensajeChat` (CU18), duplicado a proposito: ningun
/// modulo importa modelos de otro, ver CLAUDE.md.
class MensajeReporte {
  MensajeReporte({required this.rol, required this.texto});

  final String rol; // 'user' | 'assistant'
  final String texto;

  Map<String, dynamic> aJson() => {'rol': rol, 'texto': texto};
}

class ColumnaOut {
  ColumnaOut({required this.clave, required this.etiqueta});

  final String clave;
  final String etiqueta;

  factory ColumnaOut.desdeJson(Map<String, dynamic> j) =>
      ColumnaOut(clave: j['clave'] as String, etiqueta: j['etiqueta'] as String);
}

class ConsultaIaOut {
  ConsultaIaOut({
    required this.respuesta,
    required this.titulo,
    required this.columnas,
    required this.tabla,
  });

  final String respuesta;
  final String? titulo;
  final List<ColumnaOut> columnas;
  // Filas crudas de la ultima herramienta llamada por Claude (para armar una tabla generica).
  final List<Map<String, dynamic>> tabla;

  factory ConsultaIaOut.desdeJson(Map<String, dynamic> j) => ConsultaIaOut(
        respuesta: j['respuesta'] as String,
        titulo: j['titulo'] as String?,
        columnas: comoLista(j['columnas']).map(ColumnaOut.desdeJson).toList(),
        tabla: comoLista(j['tabla']),
      );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:fashionstore_movil/core/catalogo_e_inventario/inventario/inventario_service.dart';
import 'package:fashionstore_movil/core/catalogo_e_inventario/recepciones/recepciones_service.dart'
    hide VarianteBuscadaOut;
import 'package:fashionstore_movil/core/plataforma_saas/saas/saas_service.dart';

/// Los modelos que alimentan las pantallas de CU07 (selector de tienda), CU09 (recepcion con
/// impacto en el stock) y CU10 (indicadores y alertas de inventario): espejo de los schemas
/// del backend, asi que un campo renombrado alla rompe aca.
void main() {
  test('CU07: la tarjeta de tienda resume sucursales, ciudades y prendas', () {
    const tienda = TiendaOut('fashionstore', 'FashionStore',
        sucursales: 3, ciudades: ['SANTA_CRUZ', 'LA_PAZ'], prendas: 1);
    expect(tienda.resumenUbicacion, '3 sucursales · Santa Cruz, La Paz');
    expect(tienda.resumenPrendas, '1 prenda');
    expect(const TiendaOut('x', 'X', sucursales: 1).resumenUbicacion, '1 sucursal');
  });

  test('CU09: la linea trae color y stock de hoy; el asiento, talla y color', () {
    final linea = DetalleOut.desdeJson({
      'id': 'l1',
      'variante_id': 'v1',
      'sku': 'VES-001-M-NEG',
      'producto': 'Vestido',
      'talla': 'M',
      'color': 'Negro',
      'codigo_hex': '#000000',
      'cantidad': 5,
      'costo_unitario': 100,
      'subtotal': 500,
      'stock_actual': 7,
    });
    expect(linea.codigoHex, '#000000');
    expect(linea.stockActual + linea.cantidad, 12);

    final asiento = MovimientoOut.desdeJson({
      'variante_id': 'v1',
      'sku': 'VES-001-M-NEG',
      'producto': 'Vestido',
      'talla': 'M',
      'color': 'Negro',
      'codigo_hex': '#000000',
      'cantidad': 5,
      'saldo_anterior': 7,
      'saldo_nuevo': 12,
    });
    expect(asiento.talla, 'M');
    expect(asiento.saldoNuevo - asiento.saldoAnterior, asiento.cantidad);
  });

  test('CU10: el resumen y el umbral de reposicion llegan del backend', () {
    final resumen = ResumenInventarioOut.desdeJson({
      'sucursal_id': 's1',
      'sucursal': 'Equipetrol',
      'variantes': 21,
      'unidades_fisicas': 140,
      'unidades_reservadas': 6,
      'unidades_disponibles': 134,
      'agotadas': 2,
      'stock_bajo': 4,
    });
    expect(resumen.agotadas, 2);
    expect(resumen.stockBajo, 4);
    expect(AlertaInventario.bajo.name, 'bajo');
    expect(AlertaInventario.agotadas.name, 'agotadas');

    final prenda = VarianteBuscadaOut.desdeJson({
      'id': 'v1',
      'sku': 'VES-001-M-NEG',
      'producto': 'Vestido',
      'talla': 'M',
      'color': 'Negro',
      'codigo_hex': '#000000',
      'sucursal_id': 's1',
      'sucursal': 'Equipetrol',
      'cantidad_fisica': 3,
      'cantidad_reservada': 1,
      'disponible': 2,
      'stock_minimo': 5,
    });
    expect(prenda.stockMinimo, 5);
  });
}

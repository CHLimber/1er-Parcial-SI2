import '../api.dart';

/// Espejo de `backend/app/modules/caja/schemas.py` (CU07).
class CajaOut {
  CajaOut({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.tieneSesionAbierta,
  });

  final String id;
  final String codigo;
  final String nombre;
  final bool tieneSesionAbierta;

  factory CajaOut.desdeJson(Map<String, dynamic> j) => CajaOut(
        id: j['id'] as String,
        codigo: j['codigo'] as String,
        nombre: j['nombre'] as String,
        tieneSesionAbierta: j['tiene_sesion_abierta'] as bool? ?? false,
      );
}

class SesionCajaOut {
  SesionCajaOut({
    required this.id,
    required this.cajaId,
    required this.cajaNombre,
    required this.abiertaEn,
    required this.montoInicial,
    required this.estado,
  });

  final String id;
  final String cajaId;
  final String cajaNombre;
  final DateTime? abiertaEn;
  final double montoInicial;
  final String estado;

  factory SesionCajaOut.desdeJson(Map<String, dynamic> j) => SesionCajaOut(
        id: j['id'] as String,
        cajaId: j['caja_id'] as String,
        cajaNombre: j['caja_nombre'] as String,
        abiertaEn: aFechaNula(j['abierta_en']),
        montoInicial: aDouble(j['monto_inicial']),
        estado: j['estado'] as String,
      );
}

/// Prenda encontrada por SKU o codigo de barras en el mostrador.
class VarianteBusquedaOut {
  VarianteBusquedaOut({
    required this.varianteId,
    required this.sku,
    required this.producto,
    required this.talla,
    required this.color,
    required this.precio,
    required this.disponible,
  });

  final String varianteId;
  final String sku;
  final String producto;
  final String talla;
  final String color;
  final double precio;
  final int disponible;

  factory VarianteBusquedaOut.desdeJson(Map<String, dynamic> j) => VarianteBusquedaOut(
        varianteId: j['variante_id'] as String,
        sku: j['sku'] as String,
        producto: j['producto'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        precio: aDouble(j['precio']),
        disponible: aEntero(j['disponible']),
      );
}

/// CU07: sesion de caja del cajero. El backend exige sesion ABIERTA para POST /ventas/pos.
class CajaService {
  Future<List<CajaOut>> listarCajas() async {
    final respuesta = await api.get('/caja/cajas');
    return comoLista(respuesta).map(CajaOut.desdeJson).toList();
  }

  Future<SesionCajaOut?> sesionActual() async {
    final respuesta = await api.get('/caja/sesion-actual');
    if (respuesta == null) return null;
    return SesionCajaOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<SesionCajaOut> abrirSesion(String cajaId, double montoInicial) async {
    final respuesta = await api.post('/caja/abrir', cuerpo: {
      'caja_id': cajaId,
      'monto_inicial': montoInicial,
    });
    return SesionCajaOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<VarianteBusquedaOut> buscarVariante(String codigo) async {
    final respuesta = await api.get('/caja/buscar-variante', query: {'codigo': codigo});
    return VarianteBusquedaOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final cajaService = CajaService();

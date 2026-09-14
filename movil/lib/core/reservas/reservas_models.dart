import '../api.dart';

/// Espejo de `backend/app/modules/reservas/schemas.py` (CU04 y CU08).
class ReservaItemOut {
  ReservaItemOut({
    required this.id,
    required this.varianteId,
    required this.sku,
    required this.producto,
    required this.talla,
    required this.color,
    required this.cantidad,
    required this.estadoItem,
  });

  final String id;
  final String varianteId;
  final String sku;
  final String producto;
  final String talla;
  final String color;
  final int cantidad;
  final String estadoItem;

  factory ReservaItemOut.desdeJson(Map<String, dynamic> j) => ReservaItemOut(
        id: j['id'] as String,
        varianteId: j['variante_id'] as String,
        sku: j['sku'] as String,
        producto: j['producto'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        cantidad: aEntero(j['cantidad']),
        estadoItem: j['estado_item'] as String,
      );
}

class ItemRechazadoOut {
  ItemRechazadoOut({required this.varianteId, required this.sku, required this.motivo});

  final String varianteId;
  final String sku;
  final String motivo;

  factory ItemRechazadoOut.desdeJson(Map<String, dynamic> j) => ItemRechazadoOut(
        varianteId: j['variante_id'] as String,
        sku: j['sku'] as String,
        motivo: j['motivo'] as String,
      );
}

class ReservaOut {
  ReservaOut({
    required this.id,
    required this.codigo,
    required this.sucursalId,
    required this.sucursal,
    required this.estado,
    required this.fechaVisita,
    required this.horaVisita,
    required this.expiraEn,
    required this.creadaEn,
    required this.observaciones,
    required this.items,
    required this.itemsRechazados,
  });

  final String id;
  final String codigo;
  final String sucursalId;
  final String sucursal;
  final String estado;
  final String fechaVisita;
  final String horaVisita;
  final DateTime? expiraEn;
  final DateTime? creadaEn;
  final String? observaciones;
  final List<ReservaItemOut> items;
  final List<ItemRechazadoOut> itemsRechazados;

  /// Solo una reserva viva puede convertirse en carrito (CU05 desde reserva). Los
  /// estados salen del ENUM `estado_reserva` del esquema.
  bool get estaVigente =>
      estado == 'PENDIENTE' ||
      estado == 'CONFIRMADA' ||
      estado == 'PREPARADA' ||
      estado == 'CLIENTE_PRESENTE';

  factory ReservaOut.desdeJson(Map<String, dynamic> j) => ReservaOut(
        id: j['id'] as String,
        codigo: j['codigo'] as String,
        sucursalId: j['sucursal_id'] as String,
        sucursal: j['sucursal'] as String,
        estado: j['estado'] as String,
        fechaVisita: j['fecha_visita'] as String,
        horaVisita: j['hora_visita'] as String,
        expiraEn: aFechaNula(j['expira_en']),
        creadaEn: aFechaNula(j['creada_en']),
        observaciones: j['observaciones'] as String?,
        items: comoLista(j['items']).map(ReservaItemOut.desdeJson).toList(),
        itemsRechazados:
            comoLista(j['items_rechazados']).map(ItemRechazadoOut.desdeJson).toList(),
      );
}

class ClienteBreveOut {
  ClienteBreveOut({
    required this.nombre,
    required this.apellido,
    required this.email,
    required this.telefono,
  });

  final String nombre;
  final String apellido;
  final String email;
  final String? telefono;

  String get nombreCompleto => '$nombre $apellido';

  factory ClienteBreveOut.desdeJson(Map<String, dynamic> j) => ClienteBreveOut(
        nombre: j['nombre'] as String,
        apellido: j['apellido'] as String,
        email: j['email'] as String,
        telefono: j['telefono'] as String?,
      );
}

/// Vista del encargado de sucursal (CU08).
class ReservaStaffOut {
  ReservaStaffOut({
    required this.id,
    required this.codigo,
    required this.cliente,
    required this.sucursalId,
    required this.sucursal,
    required this.estado,
    required this.fechaVisita,
    required this.horaVisita,
    required this.expiraEn,
    required this.creadaEn,
    required this.observaciones,
    required this.vestidorAsignado,
    required this.atendidaEn,
    required this.items,
  });

  final String id;
  final String codigo;
  final ClienteBreveOut cliente;
  final String sucursalId;
  final String sucursal;
  final String estado;
  final String fechaVisita;
  final String horaVisita;
  final DateTime? expiraEn;
  final DateTime? creadaEn;
  final String? observaciones;
  final String? vestidorAsignado;
  final DateTime? atendidaEn;
  final List<ReservaItemOut> items;

  factory ReservaStaffOut.desdeJson(Map<String, dynamic> j) => ReservaStaffOut(
        id: j['id'] as String,
        codigo: j['codigo'] as String,
        cliente: ClienteBreveOut.desdeJson(j['cliente'] as Map<String, dynamic>),
        sucursalId: j['sucursal_id'] as String,
        sucursal: j['sucursal'] as String,
        estado: j['estado'] as String,
        fechaVisita: j['fecha_visita'] as String,
        horaVisita: j['hora_visita'] as String,
        expiraEn: aFechaNula(j['expira_en']),
        creadaEn: aFechaNula(j['creada_en']),
        observaciones: j['observaciones'] as String?,
        vestidorAsignado: j['vestidor_asignado'] as String?,
        atendidaEn: aFechaNula(j['atendida_en']),
        items: comoLista(j['items']).map(ReservaItemOut.desdeJson).toList(),
      );
}

class ResolverReservaOut {
  ResolverReservaOut({
    required this.reserva,
    required this.ventaId,
    required this.ventaNumero,
    required this.comprobanteNumero,
    required this.totalCobrado,
  });

  final ReservaStaffOut reserva;
  final String? ventaId;
  final String? ventaNumero;
  final String? comprobanteNumero;
  final double? totalCobrado;

  factory ResolverReservaOut.desdeJson(Map<String, dynamic> j) => ResolverReservaOut(
        reserva: ReservaStaffOut.desdeJson(j['reserva'] as Map<String, dynamic>),
        ventaId: j['venta_id'] as String?,
        ventaNumero: j['venta_numero'] as String?,
        comprobanteNumero: j['comprobante_numero'] as String?,
        totalCobrado: aDoubleNulo(j['total_cobrado']),
      );
}

/// Item del carrito de reserva que vive solo en el dispositivo hasta confirmar (CU04).
class ItemCarritoReserva {
  ItemCarritoReserva({
    required this.varianteId,
    required this.sku,
    required this.producto,
    required this.productoSlug,
    required this.talla,
    required this.color,
    required this.codigoHex,
    required this.precio,
    required this.imagenUrl,
    required this.cantidad,
  });

  final String varianteId;
  final String sku;
  final String producto;
  final String productoSlug;
  final String talla;
  final String color;
  final String codigoHex;
  final double precio;
  final String? imagenUrl;
  final int cantidad;

  ItemCarritoReserva copiarCon({int? cantidad}) => ItemCarritoReserva(
        varianteId: varianteId,
        sku: sku,
        producto: producto,
        productoSlug: productoSlug,
        talla: talla,
        color: color,
        codigoHex: codigoHex,
        precio: precio,
        imagenUrl: imagenUrl,
        cantidad: cantidad ?? this.cantidad,
      );

  Map<String, dynamic> aJson() => {
        'varianteId': varianteId,
        'sku': sku,
        'producto': producto,
        'productoSlug': productoSlug,
        'talla': talla,
        'color': color,
        'codigoHex': codigoHex,
        'precio': precio,
        'imagenUrl': imagenUrl,
        'cantidad': cantidad,
      };

  factory ItemCarritoReserva.desdeJson(Map<String, dynamic> j) => ItemCarritoReserva(
        varianteId: j['varianteId'] as String,
        sku: j['sku'] as String,
        producto: j['producto'] as String,
        productoSlug: j['productoSlug'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        codigoHex: j['codigoHex'] as String,
        precio: aDouble(j['precio']),
        imagenUrl: j['imagenUrl'] as String?,
        cantidad: aEntero(j['cantidad']),
      );
}

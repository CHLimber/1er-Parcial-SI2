import 'dart:convert';

import '../api.dart';

/// Espejo manual de `backend/app/modules/sincronizacion/schemas.py` y de
/// `frontend/src/app/core/sincronizacion/sincronizacion.models.ts`, armado desde las filas de
/// SQLite ([BaseLocal]) en vez de IndexedDB.

class VarianteLocal {
  const VarianteLocal({
    required this.id,
    required this.sku,
    required this.talla,
    required this.color,
    required this.codigoHex,
    required this.precio,
    required this.disponible,
  });

  factory VarianteLocal.desdeFila(Map<String, Object?> f) => VarianteLocal(
        id: f['id']! as String,
        sku: f['sku']! as String,
        talla: f['talla']! as String,
        color: f['color']! as String,
        codigoHex: f['codigo_hex']! as String,
        precio: aDouble(f['precio']),
        disponible: aEntero(f['disponible']),
      );

  final String id;
  final String sku;
  final String talla;
  final String color;
  final String codigoHex;
  final double precio;

  /// existencias conocidas de la sucursal (bajan con lo vendido/reservado en el dispositivo)
  final int disponible;
}

class ProductoLocal {
  const ProductoLocal({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.categoria,
    required this.imagenUrl,
    required this.variantes,
  });

  final String id;
  final String codigo;
  final String nombre;
  final String categoria;
  final String? imagenUrl;
  final List<VarianteLocal> variantes;
}

class ClienteLocal {
  const ClienteLocal({required this.nombre, required this.email, this.telefono});

  final String nombre;
  final String email;
  final String? telefono;
}

/// El paquete offline: sucursal autorizada + catalogo + clientas, como quedo en SQLite.
class PaqueteLocal {
  const PaqueteLocal({
    required this.empresaId,
    required this.empresa,
    required this.sucursalId,
    required this.sucursal,
    required this.sesionCajaId,
    required this.ivaTasa,
    required this.generadoEn,
    required this.productos,
    required this.clientes,
  });

  final String empresaId;
  final String empresa;
  final String sucursalId;
  final String sucursal;
  final String? sesionCajaId;
  final double ivaTasa;
  final DateTime generadoEn;
  final List<ProductoLocal> productos;
  final List<ClienteLocal> clientes;

  VarianteLocal? variante(String id) {
    for (final p in productos) {
      for (final v in p.variantes) {
        if (v.id == id) return v;
      }
    }
    return null;
  }

  String descripcionDe(String varianteId) {
    for (final p in productos) {
      for (final v in p.variantes) {
        if (v.id == varianteId) return '${p.nombre} ${v.talla}/${v.color}';
      }
    }
    return varianteId;
  }
}

/// Estado local: REGISTRADA (solo en el dispositivo) -> ENVIADA -> lo que diga el servidor.
enum EstadoLocal { registrada, enviada, confirmada, rechazada, conflicto }

EstadoLocal estadoDesde(String valor) =>
    EstadoLocal.values.firstWhere((e) => e.name.toUpperCase() == valor);

extension EstadoLocalTexto on EstadoLocal {
  String get codigo => name.toUpperCase();

  String get etiqueta => switch (this) {
        EstadoLocal.registrada => 'Solo en este equipo',
        EstadoLocal.enviada => 'Enviada, sin respuesta',
        EstadoLocal.confirmada => 'Confirmada',
        EstadoLocal.rechazada => 'Rechazada',
        EstadoLocal.conflicto => 'En conflicto',
      };

  bool get pendiente => this == EstadoLocal.registrada || this == EstadoLocal.enviada;
}

class LineaOperacion {
  const LineaOperacion({
    required this.varianteId,
    required this.cantidad,
    required this.precioUnitario,
    required this.descripcion,
  });

  final String varianteId;
  final int cantidad;
  final double precioUnitario;
  final String descripcion;
}

/// Una venta de contado o reserva registrada en el dispositivo, con su ultimo resultado.
class OperacionLocal {
  const OperacionLocal({
    required this.id,
    required this.tipo,
    required this.empresaId,
    required this.sucursalId,
    required this.usuarioId,
    required this.registradaEn,
    required this.estado,
    required this.descripcion,
    required this.total,
    required this.lineas,
    this.montoRecibido,
    this.sesionCajaId,
    this.clienteEmail,
    this.fechaVisita,
    this.horaVisita,
    this.observaciones,
    this.intentosEnvio = 0,
    this.ultimoEnvio,
    this.errorRed,
    this.codigoMotivo,
    this.motivo,
    this.resultado,
    this.duplicada = false,
    this.resueltaEn,
    this.resolucion,
  });

  factory OperacionLocal.desdeFila(Map<String, Object?> f) => OperacionLocal(
        id: f['id']! as String,
        tipo: f['tipo']! as String,
        empresaId: f['empresa_id']! as String,
        sucursalId: f['sucursal_id']! as String,
        usuarioId: f['usuario_id']! as String,
        registradaEn: DateTime.parse(f['registrada_en']! as String),
        estado: estadoDesde(f['estado']! as String),
        descripcion: f['descripcion']! as String,
        total: aDouble(f['total']),
        lineas: [
          for (final d in (f['detalle'] as List).cast<Map<String, Object?>>())
            LineaOperacion(
              varianteId: d['variante_id']! as String,
              cantidad: aEntero(d['cantidad']),
              precioUnitario: aDouble(d['precio_unitario']),
              descripcion: d['descripcion']! as String,
            ),
        ],
        montoRecibido: aDoubleNulo(f['monto_recibido']),
        sesionCajaId: f['sesion_caja_id'] as String?,
        clienteEmail: f['cliente_email'] as String?,
        fechaVisita: f['fecha_visita'] as String?,
        horaVisita: f['hora_visita'] as String?,
        observaciones: f['observaciones'] as String?,
        intentosEnvio: aEntero(f['intentos_envio']),
        ultimoEnvio: aFechaNula(f['ultimo_envio']),
        errorRed: f['error_red'] as String?,
        codigoMotivo: f['codigo_motivo'] as String?,
        motivo: f['motivo'] as String?,
        resultado: f['resultado'] == null
            ? null
            : (jsonDecode(f['resultado']! as String) as Map<String, dynamic>?),
        duplicada: aEntero(f['duplicada']) == 1,
        resueltaEn: aFechaNula(f['resuelta_en']),
        resolucion: f['resolucion'] as String?,
      );

  final String id;
  final String tipo; // VENTA | RESERVA
  final String empresaId;
  final String sucursalId;
  final String usuarioId;
  final DateTime registradaEn;
  final EstadoLocal estado;
  final String descripcion;
  final double total;
  final List<LineaOperacion> lineas;
  final double? montoRecibido;
  final String? sesionCajaId;
  final String? clienteEmail;
  final String? fechaVisita;
  final String? horaVisita;
  final String? observaciones;
  final int intentosEnvio;
  final DateTime? ultimoEnvio;
  final String? errorRed;
  final String? codigoMotivo;
  final String? motivo;
  final Map<String, dynamic>? resultado;
  final bool duplicada;
  final DateTime? resueltaEn;
  final String? resolucion;

  bool get esVenta => tipo == 'VENTA';

  /// Numero de la venta / codigo de la reserva que creo el servidor al confirmarla.
  String? get numero => (resultado?['numero'] ?? resultado?['codigo'])?.toString();

  /// El cuerpo que espera `POST /sync/operaciones` (OperacionIn del backend).
  Map<String, dynamic> aJson() => {
        'id': id,
        'tipo': tipo,
        'empresa_id': empresaId,
        'sucursal_id': sucursalId,
        'usuario_id': usuarioId,
        'registrada_en': registradaEn.toUtc().toIso8601String(),
        if (esVenta)
          'venta': {
            'items': [
              for (final l in lineas)
                {
                  'variante_id': l.varianteId,
                  'cantidad': l.cantidad,
                  'precio_unitario': l.precioUnitario.toStringAsFixed(2),
                },
            ],
            'metodo_pago': 'EFECTIVO',
            'total': total.toStringAsFixed(2),
            'monto_recibido': montoRecibido?.toStringAsFixed(2),
            'sesion_caja_id': sesionCajaId,
            'cliente_email': clienteEmail,
          }
        else
          'reserva': {
            'cliente_email': clienteEmail,
            'fecha_visita': fechaVisita,
            'hora_visita': horaVisita,
            'items': [
              for (final l in lineas) {'variante_id': l.varianteId, 'cantidad': l.cantidad},
            ],
            'observaciones': observaciones,
          },
      };
}

/// Mismo calculo que el backend (subtotal + IVA redondeado al centavo), en centavos.
double totalConIva(Iterable<(double precio, int cantidad)> lineas, [double tasa = 0.13]) {
  final subtotal = lineas.fold<int>(0, (s, l) => s + (l.$1 * 100).round() * l.$2);
  return (subtotal + (subtotal * tasa).round()) / 100;
}

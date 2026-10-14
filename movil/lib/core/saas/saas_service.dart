import '../api.dart';

/// SaaS (Segundo parcial, PENDIENTES 5.4-5.6): planes y suscripcion del tenant (sucursal).
/// Espejo de `backend/app/modules/saas/schemas.py` y de `core/saas` en la web.
class PlanOut {
  PlanOut({
    required this.codigo,
    required this.nombre,
    required this.descripcion,
    required this.precioMensual,
    required this.maxEmpleados,
    required this.maxCajas,
    required this.perfilesClientes,
    required this.traspasos,
    required this.iaReportes,
  });

  final String codigo;
  final String nombre;
  final String? descripcion;
  final double precioMensual;
  final int? maxEmpleados; // null = sin limite
  final int? maxCajas;
  final bool perfilesClientes;
  final bool traspasos;
  final bool iaReportes;

  factory PlanOut.desdeJson(Map<String, dynamic> j) => PlanOut(
        codigo: j['codigo'] as String,
        nombre: j['nombre'] as String,
        descripcion: j['descripcion'] as String?,
        precioMensual: aDouble(j['precio_mensual']),
        maxEmpleados: j['max_empleados'] as int?,
        maxCajas: j['max_cajas'] as int?,
        perfilesClientes: j['perfiles_clientes'] as bool? ?? false,
        traspasos: j['traspasos'] as bool? ?? false,
        iaReportes: j['ia_reportes'] as bool? ?? false,
      );
}

class SuscripcionOut {
  SuscripcionOut({
    required this.sucursalId,
    required this.sucursal,
    required this.plan,
    required this.estado,
    required this.vigente,
    required this.venceEn,
    required this.diasRestantes,
    required this.empleados,
    required this.cajas,
  });

  final String sucursalId;
  final String sucursal;
  final PlanOut plan;
  final String estado;
  final bool vigente;
  final DateTime venceEn;
  final int diasRestantes;
  final int empleados;
  final int cajas;

  factory SuscripcionOut.desdeJson(Map<String, dynamic> j) => SuscripcionOut(
        sucursalId: j['sucursal_id'] as String,
        sucursal: j['sucursal'] as String,
        plan: PlanOut.desdeJson(j['plan'] as Map<String, dynamic>),
        estado: j['estado'] as String,
        vigente: j['vigente'] as bool? ?? false,
        venceEn: DateTime.parse(j['vence_en'] as String),
        diasRestantes: aEntero(j['dias_restantes']),
        empleados: aEntero(j['empleados']),
        cajas: aEntero(j['cajas']),
      );
}

class SaasService {
  Future<List<PlanOut>> planes() async =>
      comoLista(await api.get('/saas/planes')).map(PlanOut.desdeJson).toList();

  /// El propio tenant; el ADMIN de la plataforma recibe todos.
  Future<List<SuscripcionOut>> suscripciones() async =>
      comoLista(await api.get('/saas/suscripciones')).map(SuscripcionOut.desdeJson).toList();

  /// Devuelve la URL del Checkout hospedado de Stripe; al volver, la web (o el webhook) aplica
  /// el pago. En el movil se abre en el navegador y despues se refresca la pantalla.
  Future<String> iniciarPago(String planCodigo, int meses, String sucursalId) async {
    final respuesta = await api.post('/saas/suscripcion/checkout', cuerpo: {
      'plan_codigo': planCodigo,
      'meses': meses,
      'sucursal_id': sucursalId,
    });
    return (respuesta as Map<String, dynamic>)['url_pago'] as String;
  }
}

final saasService = SaasService();

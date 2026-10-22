import '../../api.dart';

/// SaaS multi-tenant (tenant = empresa): planes, suscripcion de la empresa y tiendas de la
/// plataforma. Espejo de `backend/app/modules/saas/schemas.py` y de `core/saas` en la web.
class PlanOut {
  PlanOut({
    required this.codigo,
    required this.nombre,
    required this.descripcion,
    required this.precioMensual,
    required this.maxSucursales,
    required this.maxEmpleados,
    required this.maxCajas,
    required this.perfilesClientes,
    required this.traspasos,
    required this.operacionOffline,
    required this.reportes,
    required this.iaReportes,
    required this.analiticaMl,
  });

  final String codigo;
  final String nombre;
  final String? descripcion;
  final double precioMensual;
  final int? maxSucursales; // null = sin limite
  final int? maxEmpleados;
  final int? maxCajas;
  final bool perfilesClientes;
  final bool traspasos;
  final bool operacionOffline;
  final bool reportes;
  final bool iaReportes;
  final bool analiticaMl;

  factory PlanOut.desdeJson(Map<String, dynamic> j) => PlanOut(
        codigo: j['codigo'] as String,
        nombre: j['nombre'] as String,
        descripcion: j['descripcion'] as String?,
        precioMensual: aDouble(j['precio_mensual']),
        maxSucursales: j['max_sucursales'] as int?,
        maxEmpleados: j['max_empleados'] as int?,
        maxCajas: j['max_cajas'] as int?,
        perfilesClientes: j['perfiles_clientes'] as bool? ?? false,
        traspasos: j['traspasos'] as bool? ?? false,
        operacionOffline: j['operacion_offline'] as bool? ?? false,
        reportes: j['reportes'] as bool? ?? false,
        iaReportes: j['ia_reportes'] as bool? ?? false,
        analiticaMl: j['analitica_ml'] as bool? ?? false,
      );
}

class SuscripcionOut {
  SuscripcionOut({
    required this.empresaId,
    required this.empresa,
    required this.plan,
    required this.estado,
    required this.vigente,
    required this.inicio,
    required this.venceEn,
    required this.diasRestantes,
    required this.sucursales,
    required this.empleados,
    required this.cajas,
  });

  final String empresaId;
  final String empresa;
  final PlanOut plan;
  final String estado;
  final bool vigente;
  final DateTime inicio;
  final DateTime venceEn;
  final int diasRestantes;
  final int sucursales;
  final int empleados;
  final int cajas;

  factory SuscripcionOut.desdeJson(Map<String, dynamic> j) {
    final uso = j['uso'] as Map<String, dynamic>? ?? const {};
    return SuscripcionOut(
      empresaId: j['empresa_id'] as String,
      empresa: j['empresa'] as String,
      plan: PlanOut.desdeJson(j['plan'] as Map<String, dynamic>),
      estado: j['estado'] as String,
      vigente: j['vigente'] as bool? ?? false,
      inicio: DateTime.parse(j['inicio'] as String),
      venceEn: DateTime.parse(j['vence_en'] as String),
      diasRestantes: aEntero(j['dias_restantes']),
      sucursales: aEntero(uso['sucursales']),
      empleados: aEntero(uso['empleados']),
      cajas: aEntero(uso['cajas']),
    );
  }
}

class TiendaOut {
  const TiendaOut(this.slug, this.nombre);

  final String slug;
  final String nombre;
}

class SaasService {
  Future<List<PlanOut>> planes() async =>
      comoLista(await api.get('/saas/planes')).map(PlanOut.desdeJson).toList();

  /// La suscripcion de la empresa del usuario.
  Future<SuscripcionOut> suscripcion() async =>
      SuscripcionOut.desdeJson(await api.get('/saas/suscripcion') as Map<String, dynamic>);

  /// Publico: las tiendas activas de la plataforma, para el selector de la clienta.
  Future<List<TiendaOut>> tiendas() async => comoLista(await api.get('/saas/tiendas'))
      .map((t) => TiendaOut(t['slug'] as String, t['nombre'] as String))
      .toList();

  /// Devuelve la URL del Checkout hospedado de Stripe; al volver, el webhook aplica el pago.
  /// En el movil se abre en el navegador y despues se refresca la pantalla.
  Future<String> iniciarPago(String planCodigo, int meses) async {
    final respuesta = await api.post('/saas/suscripcion/checkout', cuerpo: {
      'plan_codigo': planCodigo,
      'meses': meses,
    });
    return (respuesta as Map<String, dynamic>)['url_pago'] as String;
  }
}

final saasService = SaasService();

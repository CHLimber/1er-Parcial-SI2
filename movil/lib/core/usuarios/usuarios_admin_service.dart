import '../api.dart';

/// Espejo de `backend/app/modules/usuarios/admin_schemas.py` (CU13).
class EmpleadoOut {
  EmpleadoOut({
    required this.sucursalId,
    required this.sucursal,
    required this.cargo,
    required this.ci,
    required this.fechaIngreso,
    required this.activo,
  });

  final String sucursalId;
  final String sucursal;
  final String cargo;
  final String? ci;
  final String? fechaIngreso;
  final bool activo;

  factory EmpleadoOut.desdeJson(Map<String, dynamic> j) => EmpleadoOut(
        sucursalId: j['sucursal_id'] as String,
        sucursal: j['sucursal'] as String,
        cargo: j['cargo'] as String,
        ci: j['ci'] as String?,
        fechaIngreso: j['fecha_ingreso'] as String?,
        activo: j['activo'] as bool? ?? true,
      );
}

class UsuarioAdminOut {
  UsuarioAdminOut({
    required this.id,
    required this.email,
    required this.nombre,
    required this.apellido,
    required this.telefono,
    required this.tipo,
    required this.rolId,
    required this.rol,
    required this.activo,
    required this.emailVerificado,
    required this.ultimoAcceso,
    required this.creadoEn,
    required this.empleado,
  });

  final String id;
  final String email;
  final String nombre;
  final String apellido;
  final String? telefono;
  final String tipo;
  final int? rolId;
  final String? rol;
  final bool activo;
  final bool emailVerificado;
  final DateTime? ultimoAcceso;
  final DateTime? creadoEn;
  final EmpleadoOut? empleado;

  bool get esStaff => tipo == 'STAFF';
  String get nombreCompleto => '$nombre $apellido';

  factory UsuarioAdminOut.desdeJson(Map<String, dynamic> j) => UsuarioAdminOut(
        id: j['id'] as String,
        email: j['email'] as String,
        nombre: j['nombre'] as String,
        apellido: j['apellido'] as String,
        telefono: j['telefono'] as String?,
        tipo: j['tipo'] as String,
        rolId: j['rol_id'] == null ? null : aEntero(j['rol_id']),
        rol: j['rol'] as String?,
        activo: j['activo'] as bool? ?? true,
        emailVerificado: j['email_verificado'] as bool? ?? false,
        ultimoAcceso: aFechaNula(j['ultimo_acceso']),
        creadoEn: aFechaNula(j['creado_en']),
        empleado: j['empleado'] == null
            ? null
            : EmpleadoOut.desdeJson(j['empleado'] as Map<String, dynamic>),
      );
}

class PermisoOut {
  PermisoOut({
    required this.id,
    required this.codigo,
    required this.modulo,
    required this.descripcion,
  });

  final int id;
  final String codigo;
  final String modulo;
  final String? descripcion;

  factory PermisoOut.desdeJson(Map<String, dynamic> j) => PermisoOut(
        id: aEntero(j['id']),
        codigo: j['codigo'] as String,
        modulo: j['modulo'] as String,
        descripcion: j['descripcion'] as String?,
      );
}

class RolOut {
  RolOut({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.esSistema,
    required this.usuarios,
    required this.permisos,
  });

  final int id;
  final String nombre;
  final String? descripcion;
  final bool esSistema;
  final int usuarios;
  final List<int> permisos;

  factory RolOut.desdeJson(Map<String, dynamic> j) => RolOut(
        id: aEntero(j['id']),
        nombre: j['nombre'] as String,
        descripcion: j['descripcion'] as String?,
        esSistema: j['es_sistema'] as bool? ?? false,
        usuarios: aEntero(j['usuarios']),
        permisos: (j['permisos'] as List? ?? const []).map(aEntero).toList(),
      );
}

/// Cargos posibles de `empleado.cargo` (ENUM del esquema).
const List<String> cargosEmpleado = ['ENCARGADO', 'CAJERO', 'VENDEDOR', 'ALMACEN'];

/// CU13: Gestionar Usuarios y Roles. La API autoriza por codigo de permiso, no por rol.
class UsuariosAdminService {
  Future<List<UsuarioAdminOut>> listarUsuarios({String? q, String? tipo, bool? activo}) async {
    final respuesta = await api.get('/admin/usuarios', query: {
      'q': q,
      'tipo': tipo,
      'activo': activo,
    });
    return comoLista(respuesta).map(UsuarioAdminOut.desdeJson).toList();
  }

  Future<UsuarioAdminOut> obtenerUsuario(String usuarioId) async {
    final respuesta = await api.get('/admin/usuarios/$usuarioId');
    return UsuarioAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  /// Alta de personal. El esquema exige rol_id para todo STAFF y lo ata a una sucursal.
  Future<UsuarioAdminOut> crearStaff({
    required String email,
    required String password,
    required String nombre,
    required String apellido,
    String? telefono,
    required int rolId,
    required String sucursalId,
    required String cargo,
    String? ci,
    DateTime? fechaIngreso,
  }) async {
    final respuesta = await api.post('/admin/usuarios', cuerpo: {
      'email': email,
      'password': password,
      'nombre': nombre,
      'apellido': apellido,
      'telefono': (telefono?.isEmpty ?? true) ? null : telefono,
      'rol_id': rolId,
      'sucursal_id': sucursalId,
      'cargo': cargo,
      'ci': (ci?.isEmpty ?? true) ? null : ci,
      'fecha_ingreso': fechaIngreso?.toIso8601String().split('T').first,
    });
    return UsuarioAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<UsuarioAdminOut> actualizarStaff(
    String usuarioId, {
    required String email,
    required String nombre,
    required String apellido,
    String? telefono,
    required int rolId,
    required String sucursalId,
    required String cargo,
    String? ci,
    DateTime? fechaIngreso,
  }) async {
    final respuesta = await api.put('/admin/usuarios/$usuarioId', cuerpo: {
      'email': email,
      'nombre': nombre,
      'apellido': apellido,
      'telefono': (telefono?.isEmpty ?? true) ? null : telefono,
      'rol_id': rolId,
      'sucursal_id': sucursalId,
      'cargo': cargo,
      'ci': (ci?.isEmpty ?? true) ? null : ci,
      'fecha_ingreso': fechaIngreso?.toIso8601String().split('T').first,
    });
    return UsuarioAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<UsuarioAdminOut> actualizarCliente(
    String usuarioId, {
    required String email,
    required String nombre,
    required String apellido,
    String? telefono,
  }) async {
    final respuesta = await api.put('/admin/clientes/$usuarioId', cuerpo: {
      'email': email,
      'nombre': nombre,
      'apellido': apellido,
      'telefono': (telefono?.isEmpty ?? true) ? null : telefono,
    });
    return UsuarioAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<UsuarioAdminOut> cambiarEstado(String usuarioId, bool activo) async {
    final respuesta =
        await api.patch('/admin/usuarios/$usuarioId/estado', cuerpo: {'activo': activo});
    return UsuarioAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<void> restablecerPassword(String usuarioId, String password) =>
      api.post('/admin/usuarios/$usuarioId/password', cuerpo: {'password': password});

  Future<List<PermisoOut>> listarPermisos() async {
    final respuesta = await api.get('/admin/permisos');
    return comoLista(respuesta).map(PermisoOut.desdeJson).toList();
  }

  Future<List<RolOut>> listarRoles() async {
    final respuesta = await api.get('/admin/roles');
    return comoLista(respuesta).map(RolOut.desdeJson).toList();
  }

  Future<RolOut> crearRol(String nombre, {String? descripcion}) async {
    final respuesta = await api.post('/admin/roles', cuerpo: {
      'nombre': nombre,
      'descripcion': (descripcion?.isEmpty ?? true) ? null : descripcion,
    });
    return RolOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<RolOut> actualizarRol(int rolId, String nombre, {String? descripcion}) async {
    final respuesta = await api.put('/admin/roles/$rolId', cuerpo: {
      'nombre': nombre,
      'descripcion': (descripcion?.isEmpty ?? true) ? null : descripcion,
    });
    return RolOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<RolOut> asignarPermisos(int rolId, List<int> permisos) async {
    final respuesta = await api.put('/admin/roles/$rolId/permisos', cuerpo: {'permisos': permisos});
    return RolOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<void> eliminarRol(int rolId) => api.delete('/admin/roles/$rolId');
}

final usuariosAdminService = UsuariosAdminService();

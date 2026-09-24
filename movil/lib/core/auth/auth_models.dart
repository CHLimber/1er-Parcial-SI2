/// Espejo manual de `backend/app/modules/usuarios/schemas.py`. Igual que en el frontend
/// Angular, si cambia el schema de Pydantic hay que actualizar esto a mano.
class UsuarioOut {
  const UsuarioOut({
    required this.id,
    required this.email,
    required this.nombre,
    required this.apellido,
    required this.tipo,
    required this.rol,
    required this.cargo,
    required this.permisos,
  });

  final String id;
  final String email;
  final String nombre;
  final String apellido;
  final String tipo; // CLIENTE | STAFF
  final String? rol;

  /// Cargo del empleado: ENCARGADO o CAJERO. El delivery (CU20) lo hace
  /// un servicio externo, no personal con este cargo.
  final String? cargo;

  /// Codigos de permiso del rol (CU13). Vacio para clientes.
  final List<String> permisos;

  bool get esStaff => tipo == 'STAFF';
  String get nombreCompleto => '$nombre $apellido';

  factory UsuarioOut.desdeJson(Map<String, dynamic> json) => UsuarioOut(
        id: json['id'] as String,
        email: json['email'] as String,
        nombre: json['nombre'] as String,
        apellido: json['apellido'] as String,
        tipo: json['tipo'] as String,
        rol: json['rol'] as String?,
        cargo: json['cargo'] as String?,
        permisos: (json['permisos'] as List? ?? const []).map((p) => p.toString()).toList(),
      );

  Map<String, dynamic> aJson() => {
        'id': id,
        'email': email,
        'nombre': nombre,
        'apellido': apellido,
        'tipo': tipo,
        'rol': rol,
        'cargo': cargo,
        'permisos': permisos,
      };
}

class RegistroRequest {
  const RegistroRequest({
    required this.email,
    required this.password,
    required this.nombre,
    required this.apellido,
    this.telefono,
    this.fechaNacimiento,
    this.aceptaMarketing = false,
  });

  final String email;
  final String password;
  final String nombre;
  final String apellido;
  final String? telefono;
  final DateTime? fechaNacimiento;
  final bool aceptaMarketing;

  Map<String, dynamic> aJson() => {
        'email': email,
        'password': password,
        'nombre': nombre,
        'apellido': apellido,
        if (telefono != null && telefono!.isNotEmpty) 'telefono': telefono,
        if (fechaNacimiento != null)
          'fecha_nacimiento': fechaNacimiento!.toIso8601String().split('T').first,
        'acepta_marketing': aceptaMarketing,
      };
}

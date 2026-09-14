import '../api.dart';

/// Espejo de `backend/app/modules/proveedores/schemas.py` (CU11).
class ProveedorOut {
  ProveedorOut({
    required this.id,
    required this.nombre,
    required this.nit,
    required this.contacto,
    required this.email,
    required this.telefono,
    required this.activo,
    required this.productos,
    required this.recepciones,
  });

  final String id;
  final String nombre;
  final String? nit;
  final String? contacto;
  final String? email;
  final String? telefono;
  final bool activo;

  /// Por que un proveedor no se puede dar de baja sin consecuencias.
  final int productos;
  final int recepciones;

  factory ProveedorOut.desdeJson(Map<String, dynamic> j) => ProveedorOut(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        nit: j['nit'] as String?,
        contacto: j['contacto'] as String?,
        email: j['email'] as String?,
        telefono: j['telefono'] as String?,
        activo: j['activo'] as bool? ?? true,
        productos: aEntero(j['productos']),
        recepciones: aEntero(j['recepciones']),
      );
}

class ProveedorIn {
  ProveedorIn({
    required this.nombre,
    this.nit,
    this.contacto,
    this.email,
    this.telefono,
  });

  final String nombre;
  final String? nit;
  final String? contacto;
  final String? email;
  final String? telefono;

  String? _oNulo(String? valor) => (valor == null || valor.isEmpty) ? null : valor;

  Map<String, dynamic> aJson() => {
        'nombre': nombre,
        'nit': _oNulo(nit),
        'contacto': _oNulo(contacto),
        'email': _oNulo(email),
        'telefono': _oNulo(telefono),
      };
}

/// CU11: Gestionar Proveedores.
class ProveedoresService {
  Future<List<ProveedorOut>> listar({String? q, bool? activo}) async {
    final respuesta = await api.get('/proveedores', query: {'q': q, 'activo': activo});
    return comoLista(respuesta).map(ProveedorOut.desdeJson).toList();
  }

  Future<ProveedorOut> obtener(String proveedorId) async {
    final respuesta = await api.get('/proveedores/$proveedorId');
    return ProveedorOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<ProveedorOut> crear(ProveedorIn datos) async {
    final respuesta = await api.post('/proveedores', cuerpo: datos.aJson());
    return ProveedorOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<ProveedorOut> actualizar(String proveedorId, ProveedorIn datos) async {
    final respuesta = await api.put('/proveedores/$proveedorId', cuerpo: datos.aJson());
    return ProveedorOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<ProveedorOut> cambiarEstado(String proveedorId, bool activo) async {
    final respuesta =
        await api.patch('/proveedores/$proveedorId/estado', cuerpo: {'activo': activo});
    return ProveedorOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final proveedoresService = ProveedoresService();

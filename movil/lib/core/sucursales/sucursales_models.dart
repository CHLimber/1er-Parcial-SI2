import '../api.dart';

/// Espejo de `sucursales/schemas.py` (listado publico usado por CU04 y el checkout).
class SucursalOut {
  SucursalOut({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.ciudad,
    required this.direccion,
    required this.horaApertura,
    required this.horaCierre,
    required this.cantidadVestidores,
  });

  final String id;
  final String codigo;
  final String nombre;
  final String ciudad;
  final String direccion;
  final String? horaApertura;
  final String? horaCierre;
  final int cantidadVestidores;

  String get horario {
    if (horaApertura == null || horaCierre == null) return 'Horario no informado';
    return '${horaApertura!.substring(0, 5)} a ${horaCierre!.substring(0, 5)}';
  }

  factory SucursalOut.desdeJson(Map<String, dynamic> j) => SucursalOut(
        id: j['id'] as String,
        codigo: j['codigo'] as String,
        nombre: j['nombre'] as String,
        ciudad: j['ciudad'] as String,
        direccion: j['direccion'] as String,
        horaApertura: j['hora_apertura'] as String?,
        horaCierre: j['hora_cierre'] as String?,
        cantidadVestidores: aEntero(j['cantidad_vestidores']),
      );
}

/// Espejo de `sucursales/admin_schemas.py` (CU12).
class SucursalAdminOut {
  SucursalAdminOut({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.ciudad,
    required this.direccion,
    required this.telefono,
    required this.latitud,
    required this.longitud,
    required this.horaApertura,
    required this.horaCierre,
    required this.cantidadVestidores,
    required this.activa,
    required this.empleados,
    required this.cajas,
  });

  final String id;
  final String codigo;
  final String nombre;
  final String ciudad;
  final String direccion;
  final String? telefono;
  final double? latitud;
  final double? longitud;
  final String? horaApertura;
  final String? horaCierre;
  final int cantidadVestidores;
  final bool activa;
  final int empleados;
  final int cajas;

  factory SucursalAdminOut.desdeJson(Map<String, dynamic> j) => SucursalAdminOut(
        id: j['id'] as String,
        codigo: j['codigo'] as String,
        nombre: j['nombre'] as String,
        ciudad: j['ciudad'] as String,
        direccion: j['direccion'] as String,
        telefono: j['telefono'] as String?,
        latitud: aDoubleNulo(j['latitud']),
        longitud: aDoubleNulo(j['longitud']),
        horaApertura: j['hora_apertura'] as String?,
        horaCierre: j['hora_cierre'] as String?,
        cantidadVestidores: aEntero(j['cantidad_vestidores']),
        activa: j['activa'] as bool? ?? true,
        empleados: aEntero(j['empleados']),
        cajas: aEntero(j['cajas']),
      );
}

class CajaAdminOut {
  CajaAdminOut({
    required this.id,
    required this.sucursalId,
    required this.codigo,
    required this.nombre,
    required this.activa,
    required this.sesionAbierta,
  });

  final String id;
  final String sucursalId;
  final String codigo;
  final String nombre;
  final bool activa;
  final bool sesionAbierta;

  factory CajaAdminOut.desdeJson(Map<String, dynamic> j) => CajaAdminOut(
        id: j['id'] as String,
        sucursalId: j['sucursal_id'] as String,
        codigo: j['codigo'] as String,
        nombre: j['nombre'] as String,
        activa: j['activa'] as bool? ?? true,
        sesionAbierta: j['sesion_abierta'] as bool? ?? false,
      );
}

/// Cuerpo de alta/edicion de sucursal. Las horas viajan como 'HH:MM:SS'.
class SucursalIn {
  SucursalIn({
    required this.codigo,
    required this.nombre,
    required this.ciudad,
    required this.direccion,
    this.telefono,
    this.latitud,
    this.longitud,
    this.horaApertura,
    this.horaCierre,
    this.cantidadVestidores = 0,
  });

  final String codigo;
  final String nombre;
  final String ciudad;
  final String direccion;
  final String? telefono;
  final double? latitud;
  final double? longitud;
  final String? horaApertura;
  final String? horaCierre;
  final int cantidadVestidores;

  Map<String, dynamic> aJson() => {
        'codigo': codigo,
        'nombre': nombre,
        'ciudad': ciudad,
        'direccion': direccion,
        'telefono': (telefono?.isEmpty ?? true) ? null : telefono,
        'latitud': latitud,
        'longitud': longitud,
        'hora_apertura': horaApertura,
        'hora_cierre': horaCierre,
        'cantidad_vestidores': cantidadVestidores,
      };
}

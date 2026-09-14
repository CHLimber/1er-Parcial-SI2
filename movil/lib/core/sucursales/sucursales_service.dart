import '../api.dart';
import 'sucursales_models.dart';

/// Listado publico de sucursales (lo consumen CU04 y el checkout de CU05).
class SucursalesService {
  Future<List<SucursalOut>> listar() async {
    final respuesta = await api.get('/sucursales');
    return comoLista(respuesta).map(SucursalOut.desdeJson).toList();
  }
}

/// CU12: Gestionar Sucursales (y sus cajas).
class SucursalesAdminService {
  Future<List<String>> listarCiudades() async {
    final respuesta = await api.get('/admin/sucursales/ciudades');
    return (respuesta as List).map((c) => c.toString()).toList();
  }

  Future<List<SucursalAdminOut>> listar({bool? activa}) async {
    final respuesta = await api.get('/admin/sucursales', query: {'activa': activa});
    return comoLista(respuesta).map(SucursalAdminOut.desdeJson).toList();
  }

  Future<SucursalAdminOut> obtener(String sucursalId) async {
    final respuesta = await api.get('/admin/sucursales/$sucursalId');
    return SucursalAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<SucursalAdminOut> crear(SucursalIn datos) async {
    final respuesta = await api.post('/admin/sucursales', cuerpo: datos.aJson());
    return SucursalAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<SucursalAdminOut> actualizar(String sucursalId, SucursalIn datos) async {
    final respuesta = await api.put('/admin/sucursales/$sucursalId', cuerpo: datos.aJson());
    return SucursalAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<SucursalAdminOut> cambiarEstado(String sucursalId, bool activa) async {
    final respuesta =
        await api.patch('/admin/sucursales/$sucursalId/estado', cuerpo: {'activa': activa});
    return SucursalAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<List<CajaAdminOut>> listarCajas(String sucursalId) async {
    final respuesta = await api.get('/admin/sucursales/$sucursalId/cajas');
    return comoLista(respuesta).map(CajaAdminOut.desdeJson).toList();
  }

  Future<CajaAdminOut> crearCaja(String sucursalId, String codigo, String nombre) async {
    final respuesta = await api.post(
      '/admin/sucursales/$sucursalId/cajas',
      cuerpo: {'codigo': codigo, 'nombre': nombre},
    );
    return CajaAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<CajaAdminOut> cambiarEstadoCaja(String cajaId, bool activa) async {
    final respuesta =
        await api.patch('/admin/sucursales/cajas/$cajaId/estado', cuerpo: {'activa': activa});
    return CajaAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final sucursalesService = SucursalesService();
final sucursalesAdminService = SucursalesAdminService();

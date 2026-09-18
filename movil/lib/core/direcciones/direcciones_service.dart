import '../api.dart';
import 'direcciones_models.dart';

/// CU20 - libreta de direcciones de la clienta (`/direcciones`).
class DireccionesService {
  Future<List<DireccionOut>> listar() async {
    final respuesta = await api.get('/direcciones');
    return comoLista(respuesta).map(DireccionOut.desdeJson).toList();
  }

  Future<DireccionOut> crear(DireccionIn datos) async {
    final respuesta = await api.post('/direcciones', cuerpo: datos.aJson());
    return DireccionOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<DireccionOut> actualizar(String id, DireccionIn datos) async {
    final respuesta = await api.put('/direcciones/$id', cuerpo: datos.aJson());
    return DireccionOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<DireccionOut> marcarPrincipal(String id) async {
    final respuesta = await api.post('/direcciones/$id/principal');
    return DireccionOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<void> eliminar(String id) => api.delete('/direcciones/$id');

  /// Geocodificacion directa (Pelias de openrouteservice), acotada a Bolivia.
  Future<BusquedaDireccion> buscar(String texto) async {
    final respuesta = await api.get('/direcciones/buscar', query: {'texto': texto});
    return BusquedaDireccion.desdeJson(respuesta as Map<String, dynamic>);
  }

  /// Geocodificacion inversa: que direccion hay donde quedo el pin.
  Future<BusquedaDireccion> inversa(double latitud, double longitud) async {
    final respuesta = await api.get(
      '/direcciones/inversa',
      query: {'latitud': latitud, 'longitud': longitud},
    );
    return BusquedaDireccion.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final direccionesService = DireccionesService();

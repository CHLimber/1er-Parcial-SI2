import '../api.dart';

/// Cartera y perfil de clientas de la sucursal (Segundo parcial, PENDIENTES 5.7). Espejo de
/// `backend/app/modules/clientes/schemas.py`.
const segmentos = <String, String>{
  'NUEVA': 'Nueva',
  'FRECUENTE': 'Frecuente',
  'VIP': 'VIP',
  'INACTIVA': 'Inactiva',
};

class ClienteTenantOut {
  ClienteTenantOut({
    required this.usuarioId,
    required this.nombre,
    required this.email,
    required this.compras,
    required this.totalComprado,
    required this.reservas,
    required this.segmentoSugerido,
    required this.tienePerfil,
    required this.segmento,
    required this.tallaHabitual,
    required this.estiloPreferido,
    required this.telefonoContacto,
    required this.aceptaWhatsapp,
    required this.notas,
  });

  final String usuarioId;
  final String nombre;
  final String email;
  final int compras;
  final double totalComprado;
  final int reservas;
  final String segmentoSugerido;
  final bool tienePerfil;
  final String segmento;
  final String? tallaHabitual;
  final String? estiloPreferido;
  final String? telefonoContacto;
  final bool aceptaWhatsapp;
  final String? notas;

  factory ClienteTenantOut.desdeJson(Map<String, dynamic> j) => ClienteTenantOut(
        usuarioId: j['usuario_id'] as String,
        nombre: j['nombre'] as String,
        email: j['email'] as String,
        compras: aEntero(j['compras']),
        totalComprado: aDouble(j['total_comprado']),
        reservas: aEntero(j['reservas']),
        segmentoSugerido: j['segmento_sugerido'] as String,
        tienePerfil: j['tiene_perfil'] as bool? ?? false,
        segmento: j['segmento'] as String,
        tallaHabitual: j['talla_habitual'] as String?,
        estiloPreferido: j['estilo_preferido'] as String?,
        telefonoContacto: j['telefono_contacto'] as String?,
        aceptaWhatsapp: j['acepta_whatsapp'] as bool? ?? false,
        notas: j['notas'] as String?,
      );
}

class ClientesService {
  Future<List<ClienteTenantOut>> listar({String? q, String? segmento}) async {
    final respuesta = await api.get('/clientes', query: {'q': q, 'segmento': segmento});
    return comoLista(respuesta).map(ClienteTenantOut.desdeJson).toList();
  }

  Future<ClienteTenantOut> editarPerfil(String usuarioId, Map<String, dynamic> datos) async =>
      ClienteTenantOut.desdeJson(
        await api.put('/clientes/$usuarioId/perfil', cuerpo: datos) as Map<String, dynamic>,
      );
}

final clientesService = ClientesService();

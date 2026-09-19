import '../api.dart';
import '../catalogo/catalogo_models.dart';

/// Espejo de `backend/app/modules/asistente/schemas.py` (CU18).
class MensajeChat {
  MensajeChat({required this.rol, required this.texto});

  final String rol; // 'user' | 'assistant'
  final String texto;

  Map<String, dynamic> aJson() => {'rol': rol, 'texto': texto};
}

class ChatOut {
  ChatOut({required this.respuesta, required this.productosSugeridos});

  final String respuesta;
  final List<ProductoOut> productosSugeridos;

  factory ChatOut.desdeJson(Map<String, dynamic> j) => ChatOut(
        respuesta: j['respuesta'] as String,
        productosSugeridos:
            comoLista(j['productos_sugeridos']).map(ProductoOut.desdeJson).toList(),
      );
}

import '../api.dart';
import 'asistente_models.dart';

/// CU18: Asistir al Cliente via Chatbot. El backend no persiste nada, asi que
/// mandamos la conversacion completa en cada request (espejo de `AsistenteService` web).
class AsistenteService {
  Future<ChatOut> chatear(List<MensajeChat> mensajes) async {
    final respuesta = await api.post(
      '/asistente/chat',
      cuerpo: {'mensajes': mensajes.map((m) => m.aJson()).toList()},
    );
    return ChatOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final asistenteService = AsistenteService();

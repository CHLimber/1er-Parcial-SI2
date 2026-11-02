import 'package:firebase_core/firebase_core.dart';

/// Claves del proyecto de Firebase para recibir push (FCM).
///
/// Salen de la consola de Firebase -> Configuracion del proyecto -> Tus apps -> Android
/// (o del `google-services.json`): `current_key` = apiKey, `mobilesdk_app_id` = appId,
/// `project_number` = messagingSenderId, `project_id` = projectId. NO son secretos (van dentro de
/// cualquier APK); el secreto es la cuenta de servicio, que vive solo en Railway.
///
/// Se pueden pegar abajo o pasar al compilar con `--dart-define=FIREBASE_API_KEY=...`. Con alguno
/// vacio el push queda apagado y la app funciona igual (campana dentro de la app).
class OpcionesFirebase {
  static const _apiKey = '';
  static const _appId = '';
  static const _messagingSenderId = '';
  static const _projectId = '';

  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: _apiKey);
  static const appId = String.fromEnvironment('FIREBASE_APP_ID', defaultValue: _appId);
  static const messagingSenderId =
      String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: _messagingSenderId);
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: _projectId);

  static bool get configurado =>
      apiKey.isNotEmpty && appId.isNotEmpty && messagingSenderId.isNotEmpty && projectId.isNotEmpty;

  static FirebaseOptions get actuales => const FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
      );
}

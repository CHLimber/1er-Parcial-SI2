import 'dart:io';

import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../compartido/widgets.dart';
import '../core/catalogo/catalogo_models.dart';
import '../core/config.dart';
import '../core/tema.dart';

/// CU16 nivel 2: visor 3D de la prenda, embebido en la app.
///
/// Usa `<model-viewer>` (el componente web de Google) dentro de un WebView, en vez
/// de delegar todo a Google Scene Viewer como se hacia antes. La razon es que Scene
/// Viewer es una app aparte que **solo existe si el equipo tiene servicios de Google**:
/// en un Huawei sin GMS, o en un emulador sin "Play Services para RA", el boton no
/// abria absolutamente nada. Con el visor embebido el modelo 3D siempre se ve, y la
/// realidad aumentada queda como un extra que el propio `<model-viewer>` ofrece (su
/// boton "ver en tu espacio") solo en los equipos que la soportan.
///
/// `arScale: fixed` es deliberado: los dos GLB del seed ya estan reescalados a metros
/// reales (la bota mide 31x36x35 cm, ver PENDIENTES.txt 2.8), asi que la prenda tiene
/// que aparecer en el piso con su tamano verdadero y no "ajustada" por el visor.
class Visor3dPagina extends StatelessWidget {
  const Visor3dPagina({super.key, required this.nombrePrenda, required this.modelo});

  final String nombrePrenda;
  final ImagenArOut modelo;

  /// Respaldo manual: abre el mismo modelo en Google Scene Viewer.
  ///
  /// `package=com.google.android.googlequicksearchbox` y NO `com.google.ar.core`: ese
  /// ultimo solo atiende `mode=ar_only`, y usarlo con `ar_preferred` hacia que el
  /// intent no resolviera ninguna actividad (era el bug por el que el boton "no hacia
  /// nada"). Scene Viewer ademas exige HTTPS para el archivo, por eso la URL se
  /// resuelve con `resolverUrlModeloAr`.
  Future<void> _abrirEnSceneViewer(BuildContext context) async {
    final url = Uri.encodeComponent(resolverUrlModeloAr(modelo.url));
    final intent = Uri.parse(
      'intent://arvr.google.com/scene-viewer/1.0?file=$url&mode=ar_preferred'
      '&title=${Uri.encodeComponent(nombrePrenda)}'
      '#Intent;scheme=https;package=com.google.android.googlequicksearchbox;'
      'action=android.intent.action.VIEW;S.browser_fallback_url=$url;end;',
    );
    var abierto = false;
    try {
      abierto = await launchUrl(intent, mode: LaunchMode.externalApplication);
    } catch (_) {
      abierto = false;
    }
    if (!abierto && context.mounted) {
      mostrarAviso(
        context,
        'Tu equipo no tiene el visor de RA de Google. Podes seguir viendo la prenda en 3D aca.',
        esError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Paleta.paper,
      appBar: AppBar(
        title: Text(nombrePrenda),
        actions: [
          if (Platform.isAndroid)
            IconButton(
              tooltip: 'Abrir en el visor de RA de Google',
              icon: const Icon(Icons.view_in_ar_outlined),
              onPressed: () => _abrirEnSceneViewer(context),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ModelViewer(
              src: modelo.url,
              alt: nombrePrenda,
              ar: true,
              arModes: const ['scene-viewer', 'webxr', 'quick-look'],
              arScale: ArScale.fixed,
              arPlacement: ArPlacement.floor,
              autoRotate: true,
              cameraControls: true,
              disableZoom: false,
              backgroundColor: Paleta.paper,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Text(
              'Arrastra para girar la prenda y pellizca para acercarla. Si tu equipo '
              'soporta realidad aumentada, el icono de la esquina la planta en el piso '
              'de tu habitacion a tamano real.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

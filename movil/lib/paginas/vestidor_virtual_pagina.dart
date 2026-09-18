import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../core/catalogo/catalogo_models.dart';

/// CU16 nivel 1: camara en vivo con la prenda (PNG con transparencia real)
/// anclada a los hombros detectados por ML Kit Pose Detection. El mismo
/// esquema de anclajes (`hombro_izq`/`hombro_der`/`cintura`, IMAGENES_AR.txt
/// punto 4) sirve para cualquier prenda de torso, asi que este visor no sabe
/// nada de la prenda puntual: solo recibe el PNG y sus anclajes.
///
/// Metodo: una transformacion de similitud (rotar + escalar + trasladar) lleva
/// los dos puntos `hombro_izq`/`hombro_der` del PNG exactamente sobre los
/// hombros detectados. Con eso la prenda queda del tamano correcto sin importar
/// a que distancia este la clienta, y no hace falta `escala_base` (esa columna
/// igual se guarda, por si mas adelante se quiere comparar contra el ancho de
/// hombros real para sugerir talla).
///
/// El boton "invertir lados" de la barra existe porque si la camara frontal
/// entrega el buffer ya espejado (depende del equipo), la prenda se ve cruzada;
/// con eso se corrige en vivo, sin recompilar.
class VestidorVirtualPagina extends StatefulWidget {
  const VestidorVirtualPagina({super.key, required this.nombrePrenda, required this.overlay});

  final String nombrePrenda;
  final ImagenArOut overlay;

  @override
  State<VestidorVirtualPagina> createState() => _VestidorVirtualPaginaState();
}

/// Compensacion de rotacion por orientacion del equipo. Mismo mapeo que el
/// ejemplo oficial de `google_mlkit_commons`.
const _orientacionesAndroid = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

class _VestidorVirtualPaginaState extends State<VestidorVirtualPagina> {
  final PoseDetector _detector = PoseDetector(options: PoseDetectorOptions());
  CameraController? _controller;
  CameraDescription? _camara;
  ui.Image? _imagenPrenda;
  Pose? _pose;
  Size? _tamanoImagenCamara;
  InputImageRotation _rotacion = InputImageRotation.rotation0deg;
  bool _procesandoFrame = false;
  bool _invertirLados = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    try {
      await _cargarImagenPrenda();
      final camaras = await availableCameras();
      if (camaras.isEmpty) {
        setState(() => _error = 'Este dispositivo no tiene camara disponible.');
        return;
      }
      _camara = camaras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => camaras.first,
      );
      final controlador = CameraController(
        _camara!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await controlador.initialize();
      if (!mounted) {
        await controlador.dispose();
        return;
      }
      setState(() => _controller = controlador);
      await controlador.startImageStream(_procesarFrame);
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.code == 'CameraAccessDenied'
          ? 'Para probarte la prenda necesitamos permiso de camara. '
              'Activalo en los ajustes de la app y volve a entrar.'
          : 'No se pudo abrir la camara: ${error.description ?? error.code}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo abrir la camara: $error');
    }
  }

  Future<void> _cargarImagenPrenda() async {
    final respuesta =
        await NetworkAssetBundle(Uri.parse(widget.overlay.url)).load(widget.overlay.url);
    final codec = await ui.instantiateImageCodec(respuesta.buffer.asUint8List());
    final cuadro = await codec.getNextFrame();
    if (!mounted) return;
    setState(() => _imagenPrenda = cuadro.image);
  }

  /// Arma el `InputImage` que espera ML Kit a partir del `CameraImage` crudo,
  /// resolviendo la rotacion segun sensor + orientacion del equipo. En stream
  /// solo se soporta NV21 (Android) y BGRA8888 (iOS).
  InputImage? _aInputImage(CameraImage imagen) {
    final camara = _camara;
    final controlador = _controller;
    if (camara == null || controlador == null) return null;

    InputImageRotation? rotacion;
    if (Platform.isIOS) {
      rotacion = InputImageRotationValue.fromRawValue(camara.sensorOrientation);
    } else if (Platform.isAndroid) {
      var compensacion = _orientacionesAndroid[controlador.value.deviceOrientation];
      if (compensacion == null) return null;
      if (camara.lensDirection == CameraLensDirection.front) {
        compensacion = (camara.sensorOrientation + compensacion) % 360;
      } else {
        compensacion = (camara.sensorOrientation - compensacion + 360) % 360;
      }
      rotacion = InputImageRotationValue.fromRawValue(compensacion);
    }
    if (rotacion == null) return null;

    final formato = InputImageFormatValue.fromRawValue(imagen.format.raw);
    if (formato == null || imagen.planes.length != 1) return null;
    final plano = imagen.planes.first;

    _tamanoImagenCamara = Size(imagen.width.toDouble(), imagen.height.toDouble());
    _rotacion = rotacion;

    return InputImage.fromBytes(
      bytes: plano.bytes,
      metadata: InputImageMetadata(
        size: _tamanoImagenCamara!,
        rotation: rotacion,
        format: formato,
        bytesPerRow: plano.bytesPerRow,
      ),
    );
  }

  Future<void> _procesarFrame(CameraImage imagen) async {
    if (_procesandoFrame) return;
    _procesandoFrame = true;
    try {
      final entrada = _aInputImage(imagen);
      if (entrada == null) return;
      final poses = await _detector.processImage(entrada);
      if (!mounted) return;
      setState(() => _pose = poses.isEmpty ? null : poses.first);
    } catch (_) {
      // Un frame perdido no interrumpe el visor: se descarta y sigue con el proximo.
    } finally {
      _procesandoFrame = false;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controlador = _controller;
    final imagenPrenda = _imagenPrenda;
    final listo = controlador != null && controlador.value.isInitialized && imagenPrenda != null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Probate: ${widget.nombrePrenda}'),
        actions: [
          if (listo)
            IconButton(
              tooltip: 'Invertir lados (si la prenda se ve cruzada)',
              icon: const Icon(Icons.flip),
              onPressed: () => setState(() => _invertirLados = !_invertirLados),
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white, height: 1.5),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : !listo
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : Center(
                  // La vista previa y el lienzo del overlay comparten exactamente la
                  // misma caja: asi las coordenadas de los hombros detectados caen
                  // donde corresponde, sin deformar la imagen de la camara.
                  child: AspectRatio(
                    aspectRatio: 1 / controlador.value.aspectRatio,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
                          child: CameraPreview(controlador),
                        ),
                        CustomPaint(
                          painter: _PrendaPintor(
                            pose: _pose,
                            imagen: imagenPrenda,
                            overlay: widget.overlay,
                            tamanoImagenCamara: _tamanoImagenCamara,
                            rotacion: _rotacion,
                            invertirLados: _invertirLados,
                          ),
                        ),
                        if (_pose == null)
                          const Positioned(
                            left: 0,
                            right: 0,
                            bottom: 28,
                            child: Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.all(Radius.circular(8)),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  child: Text(
                                    'Ubicate de frente, a un paso de la camara',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _PrendaPintor extends CustomPainter {
  _PrendaPintor({
    required this.pose,
    required this.imagen,
    required this.overlay,
    required this.tamanoImagenCamara,
    required this.rotacion,
    required this.invertirLados,
  });

  final Pose? pose;
  final ui.Image imagen;
  final ImagenArOut overlay;
  final Size? tamanoImagenCamara;
  final InputImageRotation rotacion;
  final bool invertirLados;

  /// Pasa la X de un landmark (en el espacio de la imagen de la camara) al
  /// lienzo. Sigue el traductor del ejemplo oficial de google_mlkit_commons:
  /// con la camara en vertical la imagen viene rotada 90/270, asi que el ancho
  /// del lienzo se compara contra el ALTO del buffer.
  double _traducirX(double x, Size lienzo, Size buffer) {
    switch (rotacion) {
      case InputImageRotation.rotation90deg:
        return x * lienzo.width / (Platform.isIOS ? buffer.width : buffer.height);
      case InputImageRotation.rotation270deg:
        return lienzo.width - x * lienzo.width / (Platform.isIOS ? buffer.width : buffer.height);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return x * lienzo.width / buffer.width;
    }
  }

  double _traducirY(double y, Size lienzo, Size buffer) {
    switch (rotacion) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return y * lienzo.height / (Platform.isIOS ? buffer.height : buffer.width);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return y * lienzo.height / buffer.height;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pose = this.pose;
    final buffer = tamanoImagenCamara;
    final anclajeIzq = overlay.hombroIzq;
    final anclajeDer = overlay.hombroDer;
    if (pose == null || buffer == null || anclajeIzq == null || anclajeDer == null) return;
    if (buffer.width == 0 || buffer.height == 0) return;

    final hombroIzqPersona = pose.landmarks[PoseLandmarkType.leftShoulder];
    final hombroDerPersona = pose.landmarks[PoseLandmarkType.rightShoulder];
    if (hombroIzqPersona == null || hombroDerPersona == null) return;

    // La vista previa se dibuja espejada (Transform.scale(-1,1) en el build),
    // asi que la X detectada tambien se espeja para caer sobre lo que se ve.
    Offset aPantalla(PoseLandmark landmark) => Offset(
          size.width - _traducirX(landmark.x, size, buffer),
          _traducirY(landmark.y, size, buffer),
        );

    // En el espejo, el hombro derecho anatomico de la persona aparece del lado
    // izquierdo de la pantalla, que es donde va `hombro_izq` del PNG (los
    // anclajes estan definidos como se VEN en la imagen, no anatomicamente).
    var destinoIzq = aPantalla(hombroDerPersona);
    var destinoDer = aPantalla(hombroIzqPersona);
    if (invertirLados) {
      final tmp = destinoIzq;
      destinoIzq = destinoDer;
      destinoDer = tmp;
    }

    final origenIzq = Offset(anclajeIzq.x * imagen.width, anclajeIzq.y * imagen.height);
    final origenDer = Offset(anclajeDer.x * imagen.width, anclajeDer.y * imagen.height);

    final vectorOrigen = origenDer - origenIzq;
    final vectorDestino = destinoDer - destinoIzq;
    if (vectorOrigen.distance == 0 || vectorDestino.distance == 0) return;

    final escala = vectorDestino.distance / vectorOrigen.distance;
    final angulo = vectorDestino.direction - vectorOrigen.direction;

    canvas.save();
    canvas.translate(destinoIzq.dx, destinoIzq.dy);
    canvas.rotate(angulo);
    canvas.scale(escala);
    canvas.translate(-origenIzq.dx, -origenIzq.dy);
    canvas.drawImage(imagen, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PrendaPintor oldDelegate) => true;
}

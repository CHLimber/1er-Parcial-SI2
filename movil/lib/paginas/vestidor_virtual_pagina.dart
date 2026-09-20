import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:share_plus/share_plus.dart';

import '../compartido/widgets.dart';
import '../core/catalogo/catalogo_models.dart';
import '../core/tema.dart';

/// CU16 nivel 1: camara en vivo con la prenda (PNG con transparencia real)
/// siguiendo el cuerpo de la clienta, con los hombros detectados por ML Kit
/// Pose Detection. El mismo esquema de anclajes (`hombro_izq`/`hombro_der`/
/// `cintura`, IMAGENES_AR.txt punto 4) sirve para cualquier prenda de torso,
/// asi que este visor no sabe nada de la prenda puntual: recibe el PNG y sus
/// anclajes.
///
/// COMO SIGUE AL CUERPO (tres piezas, en este orden):
///
/// 1. La pose se traduce a coordenadas NORMALIZADAS (0..1) de la pantalla en
///    cuanto sale del detector, y no en el pintor. Asi el resto del archivo
///    (el pintor, la foto, el suavizado) no vuelve a pensar en rotaciones ni
///    en el tamano del buffer de la camara.
/// 2. Suavizado temporal con media exponencial de paso adaptativo
///    (`_suavizar`): la deteccion cruda de ML Kit salta unos pixeles por
///    frame y la prenda "vibra" aunque la persona este quieta. Con la persona
///    quieta el filtro pesa mucho el historial (la prenda se planta), y cuando
///    hay movimiento real pesa la medicion nueva (la prenda no se queda atras).
/// 3. Ajuste al torso: los hombros dan rotacion y ancho, y las caderas dan el
///    LARGO. Antes se usaba una similitud (un unico factor de escala), asi que
///    a una persona de torso largo la prenda le quedaba corta y viceversa.
///    Ahora la escala vertical sale de la distancia hombros->caderas real,
///    acotada contra la horizontal para que la prenda no se deforme de mas.
///    Por eso el anclaje `cintura` del PNG, que antes no se usaba, ahora si.
///
/// Lo que NO hace, y no hay que prometer: oclusion, caida de tela y ajuste al
/// volumen del cuerpo. Es un overlay plano anclado al torso (IMAGENES_AR.txt
/// punto 6).
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

/// Debajo de esto se considera que el landmark es una adivinanza del detector
/// (persona de espaldas, tapada o fuera de cuadro) y se descarta el frame.
const _confianzaMinima = 0.45;

/// Cuantos frames seguidos sin una pose confiable antes de borrar la prenda.
/// Sin esta tolerancia, un parpadeo del detector hace desaparecer la prenda.
const _framesParaPerder = 8;

/// Pose ya lista para dibujar: coordenadas normalizadas (0..1) sobre la
/// pantalla, con el espejo de la camara frontal ya aplicado.
class _Seguimiento {
  const _Seguimiento({required this.hombroA, required this.hombroB, this.cadera});

  /// Hombro que cae mas a la IZQUIERDA de la pantalla.
  final Offset hombroA;

  /// Hombro que cae mas a la DERECHA de la pantalla.
  final Offset hombroB;

  /// Punto medio de las caderas. Null si la persona esta cortada de la cintura
  /// para arriba: ahi se cae al ajuste proporcional.
  final Offset? cadera;
}

class _VestidorVirtualPaginaState extends State<VestidorVirtualPagina> {
  final PoseDetector _detector = PoseDetector(options: PoseDetectorOptions());

  /// El seguimiento se publica por un notifier y no por setState: la pose
  /// cambia en cada frame de la camara y no hay por que reconstruir la pagina
  /// entera para mover la prenda; el CustomPaint se repinta solo.
  final ValueNotifier<_Seguimiento?> _seguimiento = ValueNotifier(null);

  CameraController? _controller;
  CameraDescription? _camara;
  List<CameraDescription> _camaras = const [];
  ui.Image? _imagenPrenda;
  Size? _tamanoImagenCamara;
  InputImageRotation _rotacion = InputImageRotation.rotation0deg;
  bool _procesandoFrame = false;

  /// Corrige el caso en que la camara entrega el buffer YA espejado (pasa en
  /// algunos equipos y en el emulador con una webcam de laptop). Ahi la vista
  /// previa se ve bien pero la pose viene invertida, y la prenda aparece del
  /// lado opuesto del cuerpo. No se puede detectar solo: es un boton.
  bool _espejoInvertido = false;
  bool _sacandoFoto = false;
  double _ajusteTamano = 1.0;
  double _aspectoVista = 0;
  int _framesSinPose = 0;
  String? _error;

  /// La vista previa se muestra en espejo solo si estamos usando la camara frontal.
  bool get _espejada => _camara?.lensDirection == CameraLensDirection.front;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    try {
      await _cargarImagenPrenda();
      _camaras = await availableCameras();
      if (_camaras.isEmpty) {
        setState(() => _error = 'Este dispositivo no tiene camara disponible.');
        return;
      }
      final frontal = _camaras.where((c) => c.lensDirection == CameraLensDirection.front);
      await _usarCamara(frontal.isNotEmpty ? frontal.first : _camaras.first);
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

  Future<void> _usarCamara(CameraDescription camara) async {
    await _controller?.dispose();
    _controller = null;
    _seguimiento.value = null;

    final controlador = CameraController(
      camara,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await controlador.initialize();
    if (!mounted) {
      await controlador.dispose();
      return;
    }
    setState(() {
      _camara = camara;
      _controller = controlador;
    });
    await controlador.startImageStream(_procesarFrame);
  }

  /// Rota entre las camaras del equipo (frontal <-> trasera). Sirve para que
  /// una amiga pueda sacarte la foto con la prenda puesta, que en el probador
  /// de una tienda es exactamente lo que pasa.
  Future<void> _cambiarCamara() async {
    if (_camaras.length < 2 || _controller == null) return;
    final indice = _camaras.indexOf(_camara!);
    final siguiente = _camaras[(indice + 1) % _camaras.length];
    try {
      await _usarCamara(siguiente);
    } on CameraException catch (error) {
      if (!mounted) return;
      mostrarAviso(context, 'No se pudo cambiar de camara: ${error.code}', esError: true);
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
    // Proporcion de la imagen TAL COMO SE VE (ya rotada). Con la camara en
    // vertical el buffer viene apaisado, asi que ancho y alto se invierten.
    final vertical = rotacion == InputImageRotation.rotation90deg ||
        rotacion == InputImageRotation.rotation270deg;
    _aspectoVista = vertical
        ? imagen.height / imagen.width
        : imagen.width / imagen.height;

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
    if (_procesandoFrame || _sacandoFoto) return;
    _procesandoFrame = true;
    try {
      final entrada = _aInputImage(imagen);
      if (entrada == null) return;
      final poses = await _detector.processImage(entrada);
      if (!mounted) return;
      _actualizarSeguimiento(poses.isEmpty ? null : poses.first);
    } catch (_) {
      // Un frame perdido no interrumpe el visor: se descarta y sigue con el proximo.
    } finally {
      _procesandoFrame = false;
    }
  }

  /// Pasa la pose cruda de ML Kit a `_Seguimiento` (normalizado, espejado y
  /// suavizado), o la descarta si el detector no esta seguro de lo que ve.
  void _actualizarSeguimiento(Pose? pose) {
    final buffer = _tamanoImagenCamara;
    final hombroIzq = pose?.landmarks[PoseLandmarkType.leftShoulder];
    final hombroDer = pose?.landmarks[PoseLandmarkType.rightShoulder];

    final confiable = buffer != null &&
        buffer.width > 0 &&
        buffer.height > 0 &&
        hombroIzq != null &&
        hombroDer != null &&
        hombroIzq.likelihood >= _confianzaMinima &&
        hombroDer.likelihood >= _confianzaMinima;

    if (!confiable) {
      // Tolerancia a parpadeos: recien despues de varios frames seguidos sin
      // pose se borra la prenda, para que no titile.
      _framesSinPose++;
      if (_framesSinPose >= _framesParaPerder) _seguimiento.value = null;
      return;
    }
    _framesSinPose = 0;

    var puntoA = _aPantalla(hombroIzq, buffer);
    var puntoB = _aPantalla(hombroDer, buffer);
    // Los anclajes del PNG estan definidos como se VEN en la imagen, no
    // anatomicamente. Asignando por posicion en pantalla (el de menor X va al
    // anclaje izquierdo) el visor queda indiferente al espejo de la camara.
    if (puntoA.dx > puntoB.dx) {
      final tmp = puntoA;
      puntoA = puntoB;
      puntoB = tmp;
    }

    // Las caderas pueden faltar (persona cortada a la cintura) o venir con
    // poca confianza; ahi el largo se estima desde el ancho de hombros.
    final caderaIzq = pose!.landmarks[PoseLandmarkType.leftHip];
    final caderaDer = pose.landmarks[PoseLandmarkType.rightHip];
    Offset? cadera;
    if (caderaIzq != null &&
        caderaDer != null &&
        caderaIzq.likelihood >= _confianzaMinima &&
        caderaDer.likelihood >= _confianzaMinima) {
      final a = _aPantalla(caderaIzq, buffer);
      final b = _aPantalla(caderaDer, buffer);
      cadera = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    }

    final previo = _seguimiento.value;
    _seguimiento.value = _Seguimiento(
      hombroA: _suavizar(previo?.hombroA, puntoA),
      hombroB: _suavizar(previo?.hombroB, puntoB),
      cadera: cadera == null ? null : _suavizar(previo?.cadera, cadera),
    );
  }

  /// Media exponencial de paso adaptativo. Con la persona quieta el filtro
  /// pesa el historial y la prenda deja de vibrar; ante un movimiento real
  /// pesa la medicion nueva y la prenda no se arrastra atras del cuerpo.
  Offset _suavizar(Offset? previo, Offset actual) {
    if (previo == null) return actual;
    final alfa = (actual - previo).distance > 0.05 ? 0.7 : 0.25;
    return previo * (1 - alfa) + actual * alfa;
  }

  /// Landmark -> coordenada normalizada (0..1) de la PANTALLA. Resuelve de una
  /// vez la rotacion del buffer (con la camara en vertical la imagen viene
  /// rotada 90/270, asi que el ancho de pantalla se compara contra el alto del
  /// buffer) y el espejo de la camara frontal.
  Offset _aPantalla(PoseLandmark landmark, Size buffer) {
    double x;
    double y;
    switch (_rotacion) {
      case InputImageRotation.rotation90deg:
        x = landmark.x / (Platform.isIOS ? buffer.width : buffer.height);
        y = landmark.y / (Platform.isIOS ? buffer.height : buffer.width);
      case InputImageRotation.rotation270deg:
        x = 1 - landmark.x / (Platform.isIOS ? buffer.width : buffer.height);
        y = landmark.y / (Platform.isIOS ? buffer.height : buffer.width);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        x = landmark.x / buffer.width;
        y = landmark.y / buffer.height;
    }
    // La vista previa se dibuja espejada con la camara frontal, asi que la pose
    // tambien -- salvo que la camara ya la entregue espejada, que es lo que
    // corrige `_espejoInvertido`.
    final espejar = _espejada != _espejoInvertido;
    return Offset(espejar ? 1 - x : x, y);
  }

  /// Saca una foto con la prenda puesta y abre el menu para compartirla.
  ///
  /// No se puede capturar la pantalla tal cual: la vista previa de la camara es
  /// una textura de la plataforma y sale en negro en un `RepaintBoundary`. Hay
  /// que pedirle la foto a la camara y volver a componer la prenda encima, con
  /// la misma transformacion que se esta viendo -- para eso el seguimiento se
  /// guarda normalizado, y sirve igual en una imagen de otra resolucion.
  Future<void> _sacarFoto() async {
    final controlador = _controller;
    final prenda = _imagenPrenda;
    if (controlador == null || prenda == null || _sacandoFoto) return;

    setState(() => _sacandoFoto = true);
    try {
      await controlador.stopImageStream();
      final capturada = await controlador.takePicture();
      final bytes = await File(capturada.path).readAsBytes();
      final foto = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;

      final compuesta = await _componerFoto(foto);
      final archivo = File('${File(capturada.path).parent.path}/fashionstore-probador.png');
      await archivo.writeAsBytes(compuesta);
      await File(capturada.path).delete();

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(archivo.path, mimeType: 'image/png')],
          text: 'Me estoy probando ${widget.nombrePrenda} en FashionStore',
        ),
      );
    } catch (error) {
      if (mounted) {
        mostrarAviso(context, 'No se pudo sacar la foto: $error', esError: true);
      }
    } finally {
      // El stream de deteccion se corta para poder disparar la foto, asi que
      // hay que reanudarlo si o si, incluso si algo fallo en el medio.
      if (mounted) {
        setState(() => _sacandoFoto = false);
        final actual = _controller;
        if (actual != null && actual.value.isInitialized && !actual.value.isStreamingImages) {
          await actual.startImageStream(_procesarFrame);
        }
      }
    }
  }

  /// Dibuja la prenda sobre la foto recien tomada y devuelve el PNG.
  Future<Uint8List> _componerFoto(ui.Image foto) async {
    // La camara entrega la foto apaisada cuando el telefono esta en vertical
    // (el sensor esta rotado 90). Se la endereza antes de componer, si no la
    // prenda cae en cualquier lado.
    final rotar = foto.width > foto.height;
    final ancho = rotar ? foto.height : foto.width;
    final alto = rotar ? foto.width : foto.height;
    final lienzo = Size(ancho.toDouble(), alto.toDouble());

    final grabador = ui.PictureRecorder();
    final canvas = Canvas(grabador);

    // Ojo con el orden: las transformaciones se acumulan, asi que la ultima
    // declarada es la primera que toca a la imagen. El espejo va escrito antes
    // porque actua sobre el lienzo YA enderezado (eje horizontal de la
    // pantalla), no sobre el eje de la foto apaisada.
    canvas.save();
    if (_espejada) {
      // La vista previa se ve en espejo, asi que la foto tambien: si no, la
      // clienta recibe una imagen invertida de la que estuvo mirando.
      canvas.translate(ancho.toDouble(), 0);
      canvas.scale(-1, 1);
    }
    if (rotar) {
      canvas.translate(ancho.toDouble(), 0);
      canvas.rotate(math.pi / 2);
    }
    canvas.drawImage(foto, Offset.zero, Paint()..filterQuality = FilterQuality.high);
    canvas.restore();

    _PrendaPintor(
      seguimiento: _seguimiento.value,
      imagen: _imagenPrenda!,
      overlay: widget.overlay,
      ajusteTamano: _ajusteTamano,
      // En la foto la imagen SI llena el lienzo (el lienzo es la foto), asi
      // que no hay franjas que compensar.
      aspectoVista: ancho / alto,
    ).paint(canvas, lienzo);

    final imagen = await grabador.endRecording().toImage(ancho, alto);
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    return datos!.buffer.asUint8List();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _detector.close();
    _seguimiento.dispose();
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
          if (listo && _camaras.length > 1)
            IconButton(
              tooltip: 'Cambiar de camara',
              icon: const Icon(Icons.cameraswitch_outlined),
              onPressed: _sacandoFoto ? null : _cambiarCamara,
            ),
          if (listo)
            IconButton(
              tooltip: 'Corregir espejo (si la prenda cae del lado opuesto)',
              icon: const Icon(Icons.flip),
              onPressed: () => setState(() => _espejoInvertido = !_espejoInvertido),
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
              : Column(
                  children: [
                    Expanded(child: _vistaCamara(controlador, imagenPrenda)),
                    _controles(),
                  ],
                ),
    );
  }

  Widget _vistaCamara(CameraController controlador, ui.Image imagenPrenda) {
    return Center(
      // La vista previa y el lienzo del overlay comparten exactamente la misma
      // caja: asi las coordenadas normalizadas de la pose caen donde
      // corresponde, sin deformar la imagen de la camara.
      child: AspectRatio(
        aspectRatio: 1 / controlador.value.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..scaleByDouble(_espejada ? -1.0 : 1.0, 1.0, 1.0, 1.0),
              child: CameraPreview(controlador),
            ),
            ValueListenableBuilder<_Seguimiento?>(
              valueListenable: _seguimiento,
              builder: (_, seguimiento, _) => CustomPaint(
                painter: _PrendaPintor(
                  seguimiento: seguimiento,
                  imagen: imagenPrenda,
                  overlay: widget.overlay,
                              ajusteTamano: _ajusteTamano,
                  aspectoVista: _aspectoVista,
                ),
              ),
            ),
            ValueListenableBuilder<_Seguimiento?>(
              valueListenable: _seguimiento,
              builder: (_, seguimiento, _) => seguimiento != null
                  ? const SizedBox.shrink()
                  : const Positioned(
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
            ),
          ],
        ),
      ),
    );
  }

  /// Barra inferior: ajuste fino del tamano + foto.
  ///
  /// El slider existe porque los anclajes del PNG estan medidos sobre una
  /// talla M: a alguien que usa XS o L la prenda le queda unos centimetros
  /// corrida y es mas honesto dejarla acomodar a mano que fingir una medicion
  /// en centimetros que la camara no puede dar.
  Widget _controles() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
      child: Row(
        children: [
          const Icon(Icons.zoom_out_map, color: Colors.white54, size: 18),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: Paleta.flame,
                thumbColor: Paleta.flame,
                inactiveTrackColor: Colors.white24,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: _ajusteTamano,
                min: 0.8,
                max: 1.3,
                onChanged: (valor) => setState(() => _ajusteTamano = valor),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Paleta.flame),
            onPressed: _sacandoFoto ? null : _sacarFoto,
            icon: _sacandoFoto
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.camera_alt_outlined, size: 18),
            label: const Text('FOTO'),
          ),
        ],
      ),
    );
  }
}

class _PrendaPintor extends CustomPainter {
  _PrendaPintor({
    required this.seguimiento,
    required this.imagen,
    required this.overlay,
    required this.ajusteTamano,
    required this.aspectoVista,
  });

  final _Seguimiento? seguimiento;
  final ui.Image imagen;
  final ImagenArOut overlay;
  final double ajusteTamano;

  /// Proporcion (ancho/alto) de la imagen de la camara tal como se ve. El
  /// lienzo del overlay ocupa toda la caja, pero la vista previa puede quedar
  /// con franjas negras adentro (el emulador con una webcam apaisada es el
  /// caso tipico). Sin esto la prenda cae corrida respecto del cuerpo, porque
  /// las coordenadas de la pose son relativas a la IMAGEN, no a la caja.
  final double aspectoVista;

  /// Cuanto puede estirarse la prenda a lo largo respecto de su ancho. Sin este
  /// tope, una deteccion mala de caderas (la clienta sentada, o media de
  /// perfil) convierte el vestido en una mancha larguisima.
  static const _estiradoMinimo = 0.75;
  static const _estiradoMaximo = 1.45;

  @override
  void paint(Canvas canvas, Size size) {
    final seguimiento = this.seguimiento;
    final anclajeIzq = overlay.hombroIzq;
    final anclajeDer = overlay.hombroDer;
    if (seguimiento == null || anclajeIzq == null || anclajeDer == null) return;

    final vista = _cajaDeLaVista(size);
    final destinoIzq = _aLienzo(seguimiento.hombroA, vista);
    final destinoDer = _aLienzo(seguimiento.hombroB, vista);

    final origenIzq = Offset(anclajeIzq.x * imagen.width, anclajeIzq.y * imagen.height);
    final origenDer = Offset(anclajeDer.x * imagen.width, anclajeDer.y * imagen.height);

    final vectorOrigen = origenDer - origenIzq;
    final vectorDestino = destinoDer - destinoIzq;
    if (vectorOrigen.distance == 0 || vectorDestino.distance == 0) return;

    final escalaAncho = vectorDestino.distance / vectorOrigen.distance;
    final angulo = vectorDestino.direction - vectorOrigen.direction;
    final escalaLargo = _escalaLargo(seguimiento, vista, escalaAncho, destinoIzq, destinoDer);

    final medioOrigen = (origenIzq + origenDer) / 2;
    final medioDestino = (destinoIzq + destinoDer) / 2;

    canvas.save();
    canvas.translate(medioDestino.dx, medioDestino.dy);
    canvas.rotate(angulo);
    // El escalado va DESPUES de rotar: asi "largo" es el eje del torso de la
    // persona y no el eje vertical de la pantalla.
    canvas.scale(escalaAncho * ajusteTamano, escalaLargo * ajusteTamano);
    canvas.translate(-medioOrigen.dx, -medioOrigen.dy);
    canvas.drawImage(imagen, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  /// Escala vertical a partir del torso real (hombros -> caderas), comparada
  /// contra la misma distancia en el PNG (hombros -> `cintura`). Si no hay
  /// caderas confiables, o el anclaje de cintura no esta cargado, cae al
  /// ajuste proporcional de siempre.
  /// Donde cae realmente la imagen de la camara dentro del lienzo (contain
  /// centrado, igual que la vista previa). Si llena la caja, devuelve la caja.
  Rect _cajaDeLaVista(Size size) {
    if (aspectoVista <= 0 || size.isEmpty) return Offset.zero & size;
    final aspectoCaja = size.width / size.height;
    if (aspectoVista > aspectoCaja) {
      final alto = size.width / aspectoVista;
      return Rect.fromLTWH(0, (size.height - alto) / 2, size.width, alto);
    }
    final ancho = size.height * aspectoVista;
    return Rect.fromLTWH((size.width - ancho) / 2, 0, ancho, size.height);
  }

  Offset _aLienzo(Offset normalizado, Rect vista) =>
      Offset(vista.left + normalizado.dx * vista.width, vista.top + normalizado.dy * vista.height);

  double _escalaLargo(
    _Seguimiento seguimiento,
    Rect vista,
    double escalaAncho,
    Offset destinoIzq,
    Offset destinoDer,
  ) {
    final anclajeCintura = overlay.cintura;
    final cadera = seguimiento.cadera;
    if (anclajeCintura == null || cadera == null) return escalaAncho;

    final anclajeIzq = overlay.hombroIzq!;
    final anclajeDer = overlay.hombroDer!;
    final medioOrigen = Offset(
      (anclajeIzq.x + anclajeDer.x) / 2 * imagen.width,
      (anclajeIzq.y + anclajeDer.y) / 2 * imagen.height,
    );
    final cinturaOrigen =
        Offset(anclajeCintura.x * imagen.width, anclajeCintura.y * imagen.height);
    final largoOrigen = (cinturaOrigen - medioOrigen).distance;
    if (largoOrigen == 0) return escalaAncho;

    final medioDestino = (destinoIzq + destinoDer) / 2;
    final largoDestino = (_aLienzo(cadera, vista) - medioDestino).distance;

    final escala = largoDestino / largoOrigen;
    return escala.clamp(escalaAncho * _estiradoMinimo, escalaAncho * _estiradoMaximo);
  }

  @override
  bool shouldRepaint(covariant _PrendaPintor oldDelegate) =>
      oldDelegate.seguimiento != seguimiento ||
      oldDelegate.ajusteTamano != ajusteTamano ||
      oldDelegate.aspectoVista != aspectoVista;
}

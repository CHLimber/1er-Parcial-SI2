import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../compartido/widgets.dart';
import '../core/asistente/asistente_models.dart';
import '../core/asistente/asistente_service.dart';
import '../core/catalogo/catalogo_models.dart';
import '../core/errores.dart';
import '../core/tema.dart';
import 'tienda_pagina.dart' show TarjetaProducto;

/// Item de la conversacion, ya con los productos que trajo esa respuesta (si los hubo).
class _MensajeVista {
  _MensajeVista({required this.mensaje, this.productos});

  final MensajeChat mensaje;
  final List<ProductoOut>? productos;
}

/// CU18 - Asistir al Cliente via Chatbot, espejo movil de `pages/asistente` en la web.
/// Sin persistencia: la conversacion vive solo en memoria, se pierde al salir de la
/// pantalla (misma decision que en la web).
class AsistentePagina extends StatefulWidget {
  const AsistentePagina({super.key});

  @override
  State<AsistentePagina> createState() => _AsistentePaginaState();
}

class _AsistentePaginaState extends State<AsistentePagina> {
  final _mensajes = <_MensajeVista>[];
  final _borrador = TextEditingController();
  final _scroll = ScrollController();
  final _voz = stt.SpeechToText();

  bool _enviando = false;
  String? _error;

  /// CU18: dictado por voz, espejo movil de la Web Speech API de `panel-reportes` (unico
  /// otro lugar del proyecto con voz). En vez de "no soportado" (ahi era por navegador), aca
  /// `_vozDisponible` queda en falso si el usuario nunca dio permiso de microfono.
  bool _vozDisponible = false;
  bool _escuchando = false;

  @override
  void initState() {
    super.initState();
    _inicializarVoz();
  }

  Future<void> _inicializarVoz() async {
    final disponible = await _voz.initialize(
      onStatus: (estado) {
        if ((estado == 'done' || estado == 'notListening') && mounted) {
          setState(() => _escuchando = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _escuchando = false);
      },
    );
    if (mounted) setState(() => _vozDisponible = disponible);
  }

  /// Mismo criterio que `alternarEscucha()` en `panel-reportes.page.ts`: una sola frase
  /// (sin resultados parciales) que, al terminar, se manda igual que un mensaje escrito.
  Future<void> _alternarEscucha() async {
    if (_escuchando) {
      await _voz.stop();
      if (mounted) setState(() => _escuchando = false);
      return;
    }
    setState(() => _escuchando = true);
    await _voz.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: 'es_BO',
        partialResults: false,
        cancelOnError: true,
      ),
      onResult: (resultado) {
        if (!resultado.finalResult) return;
        final texto = resultado.recognizedWords.trim();
        if (texto.isNotEmpty) {
          _borrador.text = texto;
          _enviar();
        }
        if (mounted) setState(() => _escuchando = false);
      },
    );
  }

  @override
  void dispose() {
    _voz.cancel();
    _borrador.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _borrador.text.trim();
    if (texto.isEmpty || _enviando) return;

    _borrador.clear();
    setState(() {
      _error = null;
      _mensajes.add(_MensajeVista(mensaje: MensajeChat(rol: 'user', texto: texto)));
      _enviando = true;
    });
    _irAlFinal();

    try {
      final historial = _mensajes.map((v) => v.mensaje).toList();
      final respuesta = await asistenteService.chatear(historial);
      if (!mounted) return;
      setState(() {
        _mensajes.add(
          _MensajeVista(
            mensaje: MensajeChat(rol: 'assistant', texto: respuesta.respuesta),
            productos: respuesta.productosSugeridos,
          ),
        );
        _enviando = false;
      });
      _irAlFinal();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = interpretarError(error);
        _enviando = false;
      });
    }
  }

  void _irAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Asistente FashionStore')),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                  itemCount: _mensajes.length + 1 + (_enviando ? 1 : 0),
                  itemBuilder: (contexto, indice) {
                    if (indice == 0) {
                      return const _Burbuja(
                        deAsistente: true,
                        child: Text(
                          '¡Hola! Contame qué estás buscando (categoría, color, talla, para '
                          'qué ocasión) y te ayudo a encontrarlo en el catálogo.',
                        ),
                      );
                    }
                    final indiceMensaje = indice - 1;
                    if (indiceMensaje >= _mensajes.length) {
                      return const _Burbuja(
                        deAsistente: true,
                        cargando: true,
                        child: Text('Escribiendo…', style: TextStyle(fontStyle: FontStyle.italic)),
                      );
                    }
                    final vista = _mensajes[indiceMensaje];
                    final esUsuario = vista.mensaje.rol == 'user';
                    return _Burbuja(
                      deAsistente: !esUsuario,
                      productos: vista.productos,
                      child: esUsuario
                          ? Text(vista.mensaje.texto)
                          : MarkdownBody(
                              data: vista.mensaje.texto,
                              selectable: false,
                              styleSheet: _hojaEstiloMarkdown(context),
                            ),
                    );
                  },
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: MensajeError(_error!),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _borrador,
                        enabled: !_enviando,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _enviar(),
                        decoration: InputDecoration(
                          hintText: _escuchando
                              ? 'Escuchando…'
                              : 'Ej: busco un vestido para una fiesta, talla M',
                        ),
                      ),
                    ),
                    if (_vozDisponible) ...[
                      const SizedBox(width: 6),
                      IconButton.filled(
                        onPressed: _enviando ? null : _alternarEscucha,
                        tooltip: _escuchando ? 'Detener dictado' : 'Dictar por voz',
                        style: IconButton.styleFrom(
                          backgroundColor: _escuchando ? Paleta.rojo : Paleta.paperLinea,
                          foregroundColor: _escuchando ? Paleta.blanco : Paleta.ink,
                        ),
                        icon: Icon(_escuchando ? Icons.mic : Icons.mic_none),
                      ),
                    ],
                    const SizedBox(width: 10),
                    IconButton.filled(
                      onPressed: _enviando ? null : _enviar,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

MarkdownStyleSheet _hojaEstiloMarkdown(BuildContext context) =>
    MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: const TextStyle(color: Paleta.ink, fontSize: 14.5, height: 1.4),
      strong: const TextStyle(color: Paleta.ink, fontWeight: FontWeight.w700),
      listBullet: const TextStyle(color: Paleta.ink, fontSize: 14.5),
      code: fuenteMono(fontSize: 12.5, color: Paleta.ink),
    );

class _Burbuja extends StatelessWidget {
  const _Burbuja({
    required this.deAsistente,
    required this.child,
    this.productos,
    this.cargando = false,
  });

  final bool deAsistente;
  final Widget child;
  final List<ProductoOut>? productos;
  final bool cargando;

  @override
  Widget build(BuildContext context) => Align(
        alignment: deAsistente ? Alignment.centerLeft : Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: deAsistente ? Paleta.blanco : Paleta.ink,
            border: deAsistente ? Border.all(color: Paleta.paperLinea) : null,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(deAsistente ? 4 : 14),
              bottomRight: Radius.circular(deAsistente ? 14 : 4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DefaultTextStyle.merge(
                style: TextStyle(
                  color: deAsistente
                      ? (cargando ? Paleta.inkSuave : Paleta.ink)
                      : Paleta.paper,
                ),
                child: child,
              ),
              if (productos != null && productos!.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 210,
                  width: MediaQuery.of(context).size.width * 0.78,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: productos!.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (contexto, indice) => SizedBox(
                      width: 148,
                      child: TarjetaProducto(producto: productos![indice]),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

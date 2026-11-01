import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../compartido/widgets.dart';
import '../../core/acceso_y_organizacion/auth/auth_service.dart';
import '../../core/errores.dart';
import '../../core/tema.dart';

/// Recuperacion de cuenta: la persona escribe su correo y recibe un enlace de un solo uso que se
/// abre en el navegador (ahi elige la contrasena nueva). Espejo de `recuperar-password.page` web.
class RecuperarPasswordPagina extends StatefulWidget {
  const RecuperarPasswordPagina({super.key});

  @override
  State<RecuperarPasswordPagina> createState() => _RecuperarPasswordPaginaState();
}

class _RecuperarPasswordPaginaState extends State<RecuperarPasswordPagina> {
  final _formulario = GlobalKey<FormState>();
  final _email = TextEditingController();

  bool _enviando = false;
  String? _error;
  String? _mensaje;
  String? _enlace;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final respuesta = await context.read<AuthService>().recuperarPassword(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _mensaje = respuesta.mensaje;
        _enlace = respuesta.enlace;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = interpretarError(error));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _abrirEnlace() async {
    final enlace = _enlace;
    if (enlace == null) return;
    await launchUrl(Uri.parse(enlace), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Paleta.paper,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Form(
                  key: _formulario,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const EtiquetaDato('Recuperar cuenta'),
                      const SizedBox(height: 8),
                      const Titular('Contrasena nueva', tamano: 34),
                      const SizedBox(height: 10),
                      const Text(
                        'Escribe el correo de tu cuenta y te enviamos un enlace para elegir una '
                        'contrasena nueva.',
                        style: TextStyle(color: Paleta.inkSuave, height: 1.45),
                      ),
                      const SizedBox(height: 24),
                      if (_mensaje != null) ...[
                        Text(_mensaje!, style: const TextStyle(height: 1.45)),
                        if (_enlace != null) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Modo demostracion (sin correo configurado): usa este enlace.',
                            style: TextStyle(color: Paleta.inkSuave),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _abrirEnlace,
                            child: const Text('ELEGIR CONTRASENA NUEVA'),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => context.go('/login'),
                          child: const Text('Volver a iniciar sesion'),
                        ),
                      ] else ...[
                        if (_error != null) ...[
                          MensajeError(_error!),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          onFieldSubmitted: (_) => _enviar(),
                          decoration: const InputDecoration(
                            labelText: 'Correo electronico',
                            hintText: 'tucorreo@ejemplo.com',
                          ),
                          validator: (valor) {
                            final texto = valor?.trim() ?? '';
                            if (texto.isEmpty) return 'Escribe tu correo';
                            if (!texto.contains('@') || !texto.contains('.')) {
                              return 'El correo no tiene un formato valido';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _enviando ? null : _enviar,
                          child: _enviando
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Paleta.blanco),
                                )
                              : const Text('ENVIARME EL ENLACE'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _enviando ? null : () => context.go('/login'),
                          child: const Text('Volver a iniciar sesion'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

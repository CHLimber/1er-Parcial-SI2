import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/carrito/carrito_service.dart';
import '../core/errores.dart';
import '../core/tema.dart';

/// CU01: Iniciar Sesion.
class LoginPagina extends StatefulWidget {
  const LoginPagina({super.key});

  @override
  State<LoginPagina> createState() => _LoginPaginaState();
}

class _LoginPaginaState extends State<LoginPagina> {
  final _formulario = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _enviando = false;
  bool _ocultarPassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      await context.read<AuthService>().iniciarSesion(_email.text.trim(), _password.text);
      if (!mounted) return;
      await context.read<CarritoService>().refrescar();
      if (!mounted) return;
      context.go('/tienda');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = interpretarError(error));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
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
                      const EtiquetaDato('Bolivia · desde 2014'),
                      const SizedBox(height: 8),
                      const Titular('FashionStore', tamano: 42),
                      const SizedBox(height: 10),
                      const Text(
                        'Entra con tu cuenta para ver el catalogo, reservar en el vestidor '
                        'y comprar desde el celular.',
                        style: TextStyle(color: Paleta.inkSuave, height: 1.45),
                      ),
                      const SizedBox(height: 28),
                      if (_error != null) ...[
                        MensajeError(_error!),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
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
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        obscureText: _ocultarPassword,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _ingresar(),
                        decoration: InputDecoration(
                          labelText: 'Contrasena',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _ocultarPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(() => _ocultarPassword = !_ocultarPassword),
                          ),
                        ),
                        validator: (valor) =>
                            (valor == null || valor.isEmpty) ? 'Escribe tu contrasena' : null,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _enviando ? null : _ingresar,
                        child: _enviando
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Paleta.blanco),
                              )
                            : const Text('INGRESAR'),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('No tienes cuenta?', style: TextStyle(color: Paleta.inkSuave)),
                          TextButton(
                            onPressed: _enviando ? null : () => context.go('/registro'),
                            child: const Text('Crear una'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

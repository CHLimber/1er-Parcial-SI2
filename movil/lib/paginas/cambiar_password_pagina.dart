import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/errores.dart';
import '../core/tema.dart';

/// Cambiar mi propia contrasena: para CLIENTE y STAFF (cualquiera logueado), a diferencia
/// de CU13 (`panel_usuarios_pagina.dart`), que resetea la de otro sin conocer la actual.
/// Se llega aca desde `cuenta_pagina.dart`.
class CambiarPasswordPagina extends StatefulWidget {
  const CambiarPasswordPagina({super.key});

  @override
  State<CambiarPasswordPagina> createState() => _CambiarPasswordPaginaState();
}

class _CambiarPasswordPaginaState extends State<CambiarPasswordPagina> {
  final _formulario = GlobalKey<FormState>();
  final _passwordActual = TextEditingController();
  final _passwordNueva = TextEditingController();
  final _confirmarPassword = TextEditingController();

  bool _ocultarPassword = true;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    for (final control in [_passwordActual, _passwordNueva, _confirmarPassword]) {
      control.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      await context
          .read<AuthService>()
          .cambiarPassword(_passwordActual.text, _passwordNueva.text);
      if (!mounted) return;
      mostrarAviso(context, 'Tu contrasena se actualizo correctamente.');
      _passwordActual.clear();
      _passwordNueva.clear();
      _confirmarPassword.clear();
      _formulario.currentState!.reset();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = interpretarError(error));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Cambiar contrasena')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formulario,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Titular('Tu contrasena', tamano: 26),
                    const SizedBox(height: 8),
                    const Text(
                      'Para cambiarla necesitamos que confirmes la actual.',
                      style: TextStyle(color: Paleta.inkSuave, height: 1.45),
                    ),
                    const SizedBox(height: 22),
                    if (_error != null) ...[MensajeError(_error!), const SizedBox(height: 16)],
                    TextFormField(
                      controller: _passwordActual,
                      obscureText: _ocultarPassword,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Contrasena actual',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _ocultarPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(() => _ocultarPassword = !_ocultarPassword),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Ingresa tu contrasena actual' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordNueva,
                      obscureText: _ocultarPassword,
                      decoration: const InputDecoration(labelText: 'Contrasena nueva'),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final mensaje = validarPassword(v);
                        if (mensaje != null) return mensaje;
                        if (v == _passwordActual.text) {
                          return 'La contrasena nueva no puede ser igual a la actual';
                        }
                        return null;
                      },
                    ),
                    ListaRequisitosPassword(password: _passwordNueva.text),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _confirmarPassword,
                      obscureText: _ocultarPassword,
                      decoration: const InputDecoration(labelText: 'Confirmar contrasena nueva'),
                      validator: (v) => v != _passwordNueva.text
                          ? 'Las contrasenas no coinciden'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: _enviando ? null : _guardar,
                      child: _enviando
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Paleta.blanco,
                              ),
                            )
                          : const Text('GUARDAR CONTRASENA'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

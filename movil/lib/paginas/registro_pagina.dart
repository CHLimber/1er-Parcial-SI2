import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/auth/auth_models.dart';
import '../core/auth/auth_service.dart';
import '../core/carrito/carrito_service.dart';
import '../core/errores.dart';
import '../core/tema.dart';

/// CU02: Registrarse. Solo crea cuentas CLIENTE; el alta de personal es del
/// administrador (CU13).
class RegistroPagina extends StatefulWidget {
  const RegistroPagina({super.key});

  @override
  State<RegistroPagina> createState() => _RegistroPaginaState();
}

class _RegistroPaginaState extends State<RegistroPagina> {
  final _formulario = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _apellido = TextEditingController();
  final _email = TextEditingController();
  final _telefono = TextEditingController();
  final _password = TextEditingController();
  final _repetirPassword = TextEditingController();

  DateTime? _fechaNacimiento;
  bool _aceptaMarketing = false;
  bool _ocultarPassword = true;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    for (final control in [_nombre, _apellido, _email, _telefono, _password, _repetirPassword]) {
      control.dispose();
    }
    super.dispose();
  }

  /// Misma regla que `RegistroRequest.password_segura` en el backend.
  String? _validarPassword(String? valor) {
    final texto = valor ?? '';
    if (texto.length < 8) return 'Debe tener al menos 8 caracteres';
    if (!RegExp(r'[a-z]').hasMatch(texto)) return 'Debe tener al menos una letra minuscula';
    if (!RegExp(r'[A-Z]').hasMatch(texto)) return 'Debe tener al menos una letra mayuscula';
    if (!RegExp(r'\d').hasMatch(texto)) return 'Debe tener al menos un numero';
    return null;
  }

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fechaNacimiento ?? DateTime(hoy.year - 25),
      firstDate: DateTime(hoy.year - 100),
      lastDate: hoy,
      helpText: 'Fecha de nacimiento',
    );
    if (elegida != null) setState(() => _fechaNacimiento = elegida);
  }

  Future<void> _registrarse() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      await context.read<AuthService>().registrarse(
            RegistroRequest(
              email: _email.text.trim(),
              password: _password.text,
              nombre: _nombre.text.trim(),
              apellido: _apellido.text.trim(),
              telefono: _telefono.text.trim(),
              fechaNacimiento: _fechaNacimiento,
              aceptaMarketing: _aceptaMarketing,
            ),
          );
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
        appBar: AppBar(
          title: const Text('Crear cuenta'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/login'),
          ),
        ),
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
                    const Titular('Bienvenido a la tienda', tamano: 28),
                    const SizedBox(height: 8),
                    const Text(
                      'Tu cuenta te deja reservar prendas en el vestidor de una sucursal '
                      'y comprar en linea.',
                      style: TextStyle(color: Paleta.inkSuave, height: 1.45),
                    ),
                    const SizedBox(height: 22),
                    if (_error != null) ...[MensajeError(_error!), const SizedBox(height: 16)],
                    TextFormField(
                      controller: _nombre,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                      validator: (v) =>
                          (v?.trim().isEmpty ?? true) ? 'Escribe tu nombre' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _apellido,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Apellido'),
                      validator: (v) =>
                          (v?.trim().isEmpty ?? true) ? 'Escribe tu apellido' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Correo electronico'),
                      validator: (v) {
                        final texto = v?.trim() ?? '';
                        if (texto.isEmpty) return 'Escribe tu correo';
                        if (!texto.contains('@') || !texto.contains('.')) {
                          return 'El correo no tiene un formato valido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _telefono,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Telefono (opcional)',
                        hintText: '7xxxxxxx',
                      ),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: _elegirFecha,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha de nacimiento (opcional)',
                        ),
                        child: Text(
                          _fechaNacimiento == null
                              ? 'Sin especificar'
                              : _fechaNacimiento!.toIso8601String().split('T').first,
                          style: TextStyle(
                            color: _fechaNacimiento == null ? Paleta.inkSuave : Paleta.ink,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _ocultarPassword,
                      decoration: InputDecoration(
                        labelText: 'Contrasena',
                        helperText: 'Minimo 8 caracteres, con mayuscula, minuscula y numero',
                        helperMaxLines: 2,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _ocultarPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(() => _ocultarPassword = !_ocultarPassword),
                        ),
                      ),
                      validator: _validarPassword,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _repetirPassword,
                      obscureText: _ocultarPassword,
                      decoration: const InputDecoration(labelText: 'Repetir contrasena'),
                      validator: (v) =>
                          v != _password.text ? 'Las contrasenas no coinciden' : null,
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      value: _aceptaMarketing,
                      onChanged: (v) => setState(() => _aceptaMarketing = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: Paleta.flame,
                      title: const Text(
                        'Quiero recibir novedades y promociones',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: _enviando ? null : _registrarse,
                      child: _enviando
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Paleta.blanco,
                              ),
                            )
                          : const Text('CREAR CUENTA'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Ya tienes cuenta?', style: TextStyle(color: Paleta.inkSuave)),
                        TextButton(
                          onPressed: _enviando ? null : () => context.go('/login'),
                          child: const Text('Iniciar sesion'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

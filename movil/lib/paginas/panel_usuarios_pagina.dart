import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/errores.dart';
import '../core/sucursales/sucursales_models.dart';
import '../core/sucursales/sucursales_service.dart';
import '../core/tema.dart';
import '../core/usuarios/usuarios_admin_service.dart';
import 'mis_reservas_pagina.dart' show fechaLegible;

/// CU13: Gestionar Usuarios y Roles. La API autoriza por codigo de permiso; esta pantalla
/// es la que reparte esos codigos entre los roles.
class PanelUsuariosPagina extends StatelessWidget {
  const PanelUsuariosPagina({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final puedeVerRoles = auth.tienePermiso(['roles.ver', 'roles.gestionar']);
    final puedeVerUsuarios = auth.tienePermiso(['usuarios.ver', 'usuarios.gestionar']);

    final pestanas = <Tab>[
      if (puedeVerUsuarios) const Tab(text: 'USUARIOS'),
      if (puedeVerRoles) const Tab(text: 'ROLES'),
    ];
    final vistas = <Widget>[
      if (puedeVerUsuarios) const _PestanaUsuarios(),
      if (puedeVerRoles) const _PestanaRoles(),
    ];

    if (pestanas.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Usuarios y roles')),
        body: const EstadoVacio(
          mensaje: 'Tu rol no puede ver el padron de usuarios ni los roles.',
          icono: Icons.lock_outline,
        ),
      );
    }

    return DefaultTabController(
      length: pestanas.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Usuarios y roles'),
          bottom: TabBar(
            labelColor: Paleta.paper,
            unselectedLabelColor: Paleta.paperLinea,
            indicatorColor: Paleta.flame,
            tabs: pestanas,
          ),
        ),
        body: TabBarView(children: vistas),
      ),
    );
  }
}

// --- Usuarios --------------------------------------------------------------

class _PestanaUsuarios extends StatefulWidget {
  const _PestanaUsuarios();

  @override
  State<_PestanaUsuarios> createState() => _PestanaUsuariosState();
}

class _PestanaUsuariosState extends State<_PestanaUsuarios> {
  final _busqueda = TextEditingController();

  List<UsuarioAdminOut> _usuarios = [];
  List<RolOut> _roles = [];
  List<SucursalAdminOut> _sucursales = [];
  String? _tipo;
  bool? _activo;
  bool _cargando = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final usuarios = await usuariosAdminService.listarUsuarios(
        q: _busqueda.text.trim().isEmpty ? null : _busqueda.text.trim(),
        tipo: _tipo,
        activo: _activo,
      );
      if (!mounted) return;
      setState(() {
        _usuarios = usuarios;
        _cargando = false;
      });
      // Roles y sucursales solo hacen falta para el alta de personal; si el rol no los
      // puede leer, la pantalla igual funciona en modo consulta.
      if (_roles.isEmpty) {
        try {
          _roles = await usuariosAdminService.listarRoles();
        } catch (_) {
          _roles = [];
        }
      }
      if (_sucursales.isEmpty) {
        try {
          _sucursales = await sucursalesAdminService.listar(activa: true);
        } catch (_) {
          _sucursales = [];
        }
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = interpretarError(error);
        _cargando = false;
      });
    }
  }

  void _buscarConRetraso(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _cargar);
  }

  Future<void> _formularioStaff({UsuarioAdminOut? usuario}) async {
    if (_roles.isEmpty || _sucursales.isEmpty) {
      mostrarAviso(
        context,
        'Necesitas permiso sobre roles y sucursales para dar de alta personal.',
        esError: true,
      );
      return;
    }

    final email = TextEditingController(text: usuario?.email ?? '');
    final password = TextEditingController();
    final nombre = TextEditingController(text: usuario?.nombre ?? '');
    final apellido = TextEditingController(text: usuario?.apellido ?? '');
    final telefono = TextEditingController(text: usuario?.telefono ?? '');
    final ci = TextEditingController(text: usuario?.empleado?.ci ?? '');
    final formulario = GlobalKey<FormState>();

    int? rolId = usuario?.rolId ?? _roles.first.id;
    String? sucursalId = usuario?.empleado?.sucursalId ?? _sucursales.first.id;
    String cargo = usuario?.empleado?.cargo ?? cargosEmpleado.first;
    DateTime? fechaIngreso = usuario?.empleado?.fechaIngreso == null
        ? null
        : DateTime.tryParse(usuario!.empleado!.fechaIngreso!);
    final esNuevo = usuario == null;

    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Paleta.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (contexto) => StatefulBuilder(
        builder: (contexto, actualizar) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(contexto).viewInsets.bottom),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.9,
            maxChildSize: 0.95,
            builder: (contexto, scroll) => Form(
              key: formulario,
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                children: [
                  Titular(esNuevo ? 'Alta de personal' : 'Editar personal', tamano: 24),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: nombre,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: (v) => (v?.trim().isEmpty ?? true) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: apellido,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Apellido'),
                    validator: (v) => (v?.trim().isEmpty ?? true) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo corporativo'),
                    validator: (v) =>
                        (v?.contains('@') ?? false) ? null : 'Correo invalido',
                  ),
                  if (esNuevo) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: password,
                      decoration: const InputDecoration(
                        labelText: 'Contrasena inicial',
                        helperText: 'Minimo 8, con mayuscula, minuscula y numero',
                        helperMaxLines: 2,
                      ),
                      validator: _validarPassword,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: telefono,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Telefono (opcional)'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: rolId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Rol'),
                    items: _roles
                        .map((r) => DropdownMenuItem(value: r.id, child: Text(r.nombre)))
                        .toList(),
                    onChanged: (valor) => actualizar(() => rolId = valor),
                    validator: (v) => v == null ? 'Elige un rol' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: sucursalId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Sucursal'),
                    items: _sucursales
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.nombre, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (valor) => actualizar(() => sucursalId = valor),
                    validator: (v) => v == null ? 'Elige la sucursal' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: cargo,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Cargo'),
                    items: cargosEmpleado
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (valor) => actualizar(() => cargo = valor ?? cargo),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: ci,
                    decoration: const InputDecoration(labelText: 'CI (opcional)'),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final elegida = await showDatePicker(
                        context: contexto,
                        initialDate: fechaIngreso ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (elegida != null) actualizar(() => fechaIngreso = elegida);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Fecha de ingreso'),
                      child: Text(
                        fechaIngreso == null
                            ? 'Sin especificar'
                            : fechaIngreso!.toIso8601String().split('T').first,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed: () {
                      if (formulario.currentState!.validate()) Navigator.pop(contexto, true);
                    },
                    child: const Text('GUARDAR'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final datos = (
      email: email.text.trim(),
      password: password.text,
      nombre: nombre.text.trim(),
      apellido: apellido.text.trim(),
      telefono: telefono.text.trim(),
      ci: ci.text.trim(),
    );
    for (final control in [email, password, nombre, apellido, telefono, ci]) {
      control.dispose();
    }
    if (guardado != true) return;

    try {
      if (esNuevo) {
        await usuariosAdminService.crearStaff(
          email: datos.email,
          password: datos.password,
          nombre: datos.nombre,
          apellido: datos.apellido,
          telefono: datos.telefono,
          rolId: rolId!,
          sucursalId: sucursalId!,
          cargo: cargo,
          ci: datos.ci,
          fechaIngreso: fechaIngreso,
        );
      } else {
        await usuariosAdminService.actualizarStaff(
          usuario.id,
          email: datos.email,
          nombre: datos.nombre,
          apellido: datos.apellido,
          telefono: datos.telefono,
          rolId: rolId!,
          sucursalId: sucursalId!,
          cargo: cargo,
          ci: datos.ci,
          fechaIngreso: fechaIngreso,
        );
      }
      if (!mounted) return;
      mostrarAviso(context, 'Personal guardado');
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  Future<void> _formularioCliente(UsuarioAdminOut usuario) async {
    final email = TextEditingController(text: usuario.email);
    final nombre = TextEditingController(text: usuario.nombre);
    final apellido = TextEditingController(text: usuario.apellido);
    final telefono = TextEditingController(text: usuario.telefono ?? '');

    final guardado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        backgroundColor: Paleta.blanco,
        title: const Text('Editar cliente'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombre,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: apellido,
                decoration: const InputDecoration(labelText: 'Apellido'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: email,
                decoration: const InputDecoration(labelText: 'Correo'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: telefono,
                decoration: const InputDecoration(labelText: 'Telefono'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(contexto, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    final datos = (
      email: email.text.trim(),
      nombre: nombre.text.trim(),
      apellido: apellido.text.trim(),
      telefono: telefono.text.trim(),
    );
    for (final control in [email, nombre, apellido, telefono]) {
      control.dispose();
    }
    if (guardado != true) return;

    try {
      await usuariosAdminService.actualizarCliente(
        usuario.id,
        email: datos.email,
        nombre: datos.nombre,
        apellido: datos.apellido,
        telefono: datos.telefono,
      );
      if (!mounted) return;
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  Future<void> _restablecerPassword(UsuarioAdminOut usuario) async {
    final password = TextEditingController();
    final formulario = GlobalKey<FormState>();

    final guardado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        backgroundColor: Paleta.blanco,
        title: const Text('Restablecer contrasena'),
        content: Form(
          key: formulario,
          child: TextFormField(
            controller: password,
            decoration: InputDecoration(
              labelText: 'Nueva contrasena para ${usuario.nombre}',
              helperText: 'Minimo 8, con mayuscula, minuscula y numero',
              helperMaxLines: 2,
            ),
            validator: _validarPassword,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formulario.currentState!.validate()) Navigator.pop(contexto, true);
            },
            child: const Text('Restablecer'),
          ),
        ],
      ),
    );

    final texto = password.text;
    password.dispose();
    if (guardado != true) return;

    try {
      await usuariosAdminService.restablecerPassword(usuario.id, texto);
      if (!mounted) return;
      mostrarAviso(context, 'Contrasena restablecida');
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  Future<void> _cambiarEstado(UsuarioAdminOut usuario) async {
    final activar = !usuario.activo;
    if (!activar) {
      final confirmado = await confirmar(
        context,
        titulo: 'Dar de baja',
        mensaje: '${usuario.nombreCompleto} no podra volver a iniciar sesion.',
        textoConfirmar: 'Dar de baja',
        destructivo: true,
      );
      if (!confirmado) return;
    }
    try {
      await usuariosAdminService.cambiarEstado(usuario.id, activar);
      if (!mounted) return;
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final puedeGestionar = context.watch<AuthService>().tienePermiso(['usuarios.gestionar']);

    return Scaffold(
      backgroundColor: Paleta.paper,
      floatingActionButton: puedeGestionar
          ? FloatingActionButton.extended(
              onPressed: () => _formularioStaff(),
              backgroundColor: Paleta.flame,
              foregroundColor: Paleta.blanco,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('PERSONAL'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _busqueda,
              onChanged: _buscarConRetraso,
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre, apellido o email',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip('Todos', _tipo == null && _activo == null, () {
                  setState(() {
                    _tipo = null;
                    _activo = null;
                  });
                  _cargar();
                }),
                _chip('Personal', _tipo == 'STAFF', () {
                  setState(() => _tipo = _tipo == 'STAFF' ? null : 'STAFF');
                  _cargar();
                }),
                _chip('Clientes', _tipo == 'CLIENTE', () {
                  setState(() => _tipo = _tipo == 'CLIENTE' ? null : 'CLIENTE');
                  _cargar();
                }),
                _chip('Activos', _activo == true, () {
                  setState(() => _activo = _activo == true ? null : true);
                  _cargar();
                }),
                _chip('De baja', _activo == false, () {
                  setState(() => _activo = _activo == false ? null : false);
                  _cargar();
                }),
              ],
            ),
          ),
          Expanded(
            child: VistaAsincrona(
              cargando: _cargando,
              error: _error,
              alReintentar: _cargar,
              hijo: _usuarios.isEmpty
                  ? const EstadoVacio(mensaje: 'No hay usuarios con ese criterio.')
                  : RefreshIndicator(
                      color: Paleta.flame,
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                        itemCount: _usuarios.length,
                        separatorBuilder: (contexto, indice) => const SizedBox(height: 10),
                        itemBuilder: (contexto, indice) =>
                            _tarjeta(_usuarios[indice], puedeGestionar),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String etiqueta, bool elegido, VoidCallback alTocar) => Padding(
        padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
        child: FilterChip(
          label: Text(etiqueta),
          selected: elegido,
          selectedColor: Paleta.flame.withValues(alpha: 0.16),
          onSelected: (_) => alTocar(),
        ),
      );

  Widget _tarjeta(UsuarioAdminOut usuario, bool puedeGestionar) => TarjetaPanel(
        hijo: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    usuario.nombreCompleto,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                BadgeEstado(usuario.tipo, color: Paleta.ink),
                const SizedBox(width: 6),
                BadgeEstado(usuario.activo ? 'ACTIVO' : 'DE BAJA'),
              ],
            ),
            const SizedBox(height: 6),
            EtiquetaDato(usuario.email),
            const SizedBox(height: 8),
            if (usuario.rol != null) FilaDato('Rol', usuario.rol!),
            if (usuario.empleado != null) ...[
              FilaDato('Sucursal', usuario.empleado!.sucursal),
              FilaDato('Cargo', usuario.empleado!.cargo),
              if (usuario.empleado!.ci != null) FilaDato('CI', usuario.empleado!.ci!),
            ],
            if (usuario.telefono != null) FilaDato('Telefono', usuario.telefono!),
            if (usuario.ultimoAcceso != null)
              FilaDato('Ultimo acceso', fechaLegible(usuario.ultimoAcceso!)),
            if (puedeGestionar) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => usuario.esStaff
                        ? _formularioStaff(usuario: usuario)
                        : _formularioCliente(usuario),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('EDITAR'),
                  ),
                  TextButton(
                    onPressed: () => _restablecerPassword(usuario),
                    child: const Text('CONTRASENA'),
                  ),
                  TextButton(
                    onPressed: () => _cambiarEstado(usuario),
                    style: TextButton.styleFrom(
                      foregroundColor: usuario.activo ? Paleta.rojo : Paleta.verde,
                    ),
                    child: Text(usuario.activo ? 'DAR DE BAJA' : 'REACTIVAR'),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
}

String? _validarPassword(String? valor) {
  final texto = valor ?? '';
  if (texto.length < 8) return 'Debe tener al menos 8 caracteres';
  if (!RegExp(r'[a-z]').hasMatch(texto)) return 'Debe tener al menos una letra minuscula';
  if (!RegExp(r'[A-Z]').hasMatch(texto)) return 'Debe tener al menos una letra mayuscula';
  if (!RegExp(r'\d').hasMatch(texto)) return 'Debe tener al menos un numero';
  return null;
}

// --- Roles y permisos ------------------------------------------------------

class _PestanaRoles extends StatefulWidget {
  const _PestanaRoles();

  @override
  State<_PestanaRoles> createState() => _PestanaRolesState();
}

class _PestanaRolesState extends State<_PestanaRoles> {
  List<RolOut> _roles = [];
  List<PermisoOut> _permisos = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final roles = await usuariosAdminService.listarRoles();
      final permisos = _permisos.isEmpty ? await usuariosAdminService.listarPermisos() : _permisos;
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _permisos = permisos;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = interpretarError(error);
        _cargando = false;
      });
    }
  }

  Future<void> _formularioRol({RolOut? rol}) async {
    final nombre = TextEditingController(text: rol?.nombre ?? '');
    final descripcion = TextEditingController(text: rol?.descripcion ?? '');

    final guardado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        backgroundColor: Paleta.blanco,
        title: Text(rol == null ? 'Nuevo rol' : 'Editar rol'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombre,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descripcion,
              decoration: const InputDecoration(labelText: 'Descripcion (opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(contexto, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    final textoNombre = nombre.text.trim();
    final textoDescripcion = descripcion.text.trim();
    nombre.dispose();
    descripcion.dispose();
    if (guardado != true || textoNombre.length < 2) return;

    try {
      if (rol == null) {
        await usuariosAdminService.crearRol(textoNombre, descripcion: textoDescripcion);
      } else {
        await usuariosAdminService.actualizarRol(
          rol.id,
          textoNombre,
          descripcion: textoDescripcion,
        );
      }
      if (!mounted) return;
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  /// El corazon de CU13: que codigos de permiso concede cada rol.
  Future<void> _editarPermisos(RolOut rol) async {
    // se toma antes de abrir la hoja: despues el context puede haberse desmontado
    final auth = context.read<AuthService>();
    final elegidos = {...rol.permisos};
    final porModulo = <String, List<PermisoOut>>{};
    for (final permiso in _permisos) {
      porModulo.putIfAbsent(permiso.modulo, () => []).add(permiso);
    }

    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Paleta.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (contexto) => StatefulBuilder(
        builder: (contexto, actualizar) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (contexto, scroll) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Titular('Permisos de ${rol.nombre}', tamano: 22),
                    const SizedBox(height: 4),
                    const Text(
                      'La API autoriza por codigo de permiso, no por nombre de rol.',
                      style: TextStyle(fontSize: 12.5, color: Paleta.inkSuave),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  children: porModulo.entries
                      .map(
                        (entrada) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            EtiquetaDato(entrada.key),
                            ...entrada.value.map(
                              (permiso) => CheckboxListTile(
                                value: elegidos.contains(permiso.id),
                                onChanged: (valor) => actualizar(() {
                                  if (valor == true) {
                                    elegidos.add(permiso.id);
                                  } else {
                                    elegidos.remove(permiso.id);
                                  }
                                }),
                                contentPadding: EdgeInsets.zero,
                                controlAffinity: ListTileControlAffinity.leading,
                                activeColor: Paleta.flame,
                                title: Text(
                                  permiso.codigo,
                                  style: fuenteMono(fontSize: 13, fontWeight: FontWeight.w600, color: Paleta.ink),
                                ),
                                subtitle: permiso.descripcion == null
                                    ? null
                                    : Text(
                                        permiso.descripcion!,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(contexto, true),
                    child: const Text('GUARDAR PERMISOS'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (guardado != true) return;
    try {
      await usuariosAdminService.asignarPermisos(rol.id, elegidos.toList());
      if (!mounted) return;
      mostrarAviso(context, 'Permisos actualizados');
      await _cargar();
      // si el rol tocado es el propio, la sesion local queda vieja hasta este refresco
      await auth.refrescarSesion();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  Future<void> _eliminarRol(RolOut rol) async {
    final confirmado = await confirmar(
      context,
      titulo: 'Eliminar rol',
      mensaje: 'Se elimina ${rol.nombre}. Solo es posible si ningun usuario lo tiene.',
      textoConfirmar: 'Eliminar',
      destructivo: true,
    );
    if (!confirmado) return;
    try {
      await usuariosAdminService.eliminarRol(rol.id);
      if (!mounted) return;
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final puedeGestionar = context.watch<AuthService>().tienePermiso(['roles.gestionar']);
    final codigosPorId = {for (final permiso in _permisos) permiso.id: permiso.codigo};

    return Scaffold(
      backgroundColor: Paleta.paper,
      floatingActionButton: puedeGestionar
          ? FloatingActionButton.extended(
              onPressed: () => _formularioRol(),
              backgroundColor: Paleta.flame,
              foregroundColor: Paleta.blanco,
              icon: const Icon(Icons.add),
              label: const Text('ROL'),
            )
          : null,
      body: VistaAsincrona(
        cargando: _cargando,
        error: _error,
        alReintentar: _cargar,
        hijo: _roles.isEmpty
            ? const EstadoVacio(mensaje: 'No hay roles definidos.')
            : RefreshIndicator(
                color: Paleta.flame,
                onRefresh: _cargar,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: _roles.length,
                  separatorBuilder: (contexto, indice) => const SizedBox(height: 10),
                  itemBuilder: (contexto, indice) {
                    final rol = _roles[indice];
                    return TarjetaPanel(
                      hijo: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  rol.nombre,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              if (rol.esSistema)
                                const BadgeEstado('SISTEMA', color: Paleta.ink),
                            ],
                          ),
                          if (rol.descripcion != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              rol.descripcion!,
                              style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave),
                            ),
                          ],
                          const SizedBox(height: 8),
                          FilaDato('Usuarios', '${rol.usuarios}'),
                          FilaDato('Permisos', '${rol.permisos.length}'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: rol.permisos
                                .take(6)
                                .map(
                                  (id) => BadgeEstado(
                                    codigosPorId[id] ?? '$id',
                                    color: Paleta.inkSuave,
                                  ),
                                )
                                .toList(),
                          ),
                          if (rol.permisos.length > 6)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'y ${rol.permisos.length - 6} mas',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Paleta.inkSuave,
                                ),
                              ),
                            ),
                          if (puedeGestionar) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _editarPermisos(rol),
                                  icon: const Icon(Icons.key_outlined, size: 18),
                                  label: const Text('PERMISOS'),
                                ),
                                TextButton(
                                  onPressed: () => _formularioRol(rol: rol),
                                  child: const Text('EDITAR'),
                                ),
                                if (!rol.esSistema && rol.usuarios == 0)
                                  TextButton(
                                    onPressed: () => _eliminarRol(rol),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Paleta.rojo,
                                    ),
                                    child: const Text('ELIMINAR'),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

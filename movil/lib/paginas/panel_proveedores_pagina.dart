import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/errores.dart';
import '../core/proveedores/proveedores_service.dart';
import '../core/tema.dart';

/// CU11: Gestionar Proveedores.
class PanelProveedoresPagina extends StatefulWidget {
  const PanelProveedoresPagina({super.key});

  @override
  State<PanelProveedoresPagina> createState() => _PanelProveedoresPaginaState();
}

class _PanelProveedoresPaginaState extends State<PanelProveedoresPagina> {
  final _busqueda = TextEditingController();

  List<ProveedorOut> _proveedores = [];
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
      final proveedores = await proveedoresService.listar(
        q: _busqueda.text.trim().isEmpty ? null : _busqueda.text.trim(),
        activo: _activo,
      );
      if (!mounted) return;
      setState(() {
        _proveedores = proveedores;
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

  void _buscarConRetraso(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _cargar);
  }

  Future<void> _abrirFormulario({ProveedorOut? proveedor}) async {
    final nombre = TextEditingController(text: proveedor?.nombre ?? '');
    final nit = TextEditingController(text: proveedor?.nit ?? '');
    final contacto = TextEditingController(text: proveedor?.contacto ?? '');
    final email = TextEditingController(text: proveedor?.email ?? '');
    final telefono = TextEditingController(text: proveedor?.telefono ?? '');
    final formulario = GlobalKey<FormState>();

    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Paleta.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (contexto) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(contexto).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Form(
            key: formulario,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Titular(proveedor == null ? 'Nuevo proveedor' : 'Editar proveedor', tamano: 24),
                const SizedBox(height: 18),
                TextFormField(
                  controller: nombre,
                  decoration: const InputDecoration(labelText: 'Nombre o razon social'),
                  validator: (v) => (v?.trim().length ?? 0) < 2
                      ? 'Escribe el nombre del proveedor'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: nit,
                  decoration: const InputDecoration(labelText: 'NIT (opcional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: contacto,
                  decoration: const InputDecoration(labelText: 'Persona de contacto (opcional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email (opcional)'),
                  validator: (v) {
                    final texto = v?.trim() ?? '';
                    if (texto.isEmpty) return null;
                    return texto.contains('@') ? null : 'El email no es valido';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: telefono,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Telefono (opcional)'),
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
    );

    final datos = ProveedorIn(
      nombre: nombre.text.trim(),
      nit: nit.text.trim(),
      contacto: contacto.text.trim(),
      email: email.text.trim(),
      telefono: telefono.text.trim(),
    );
    for (final control in [nombre, nit, contacto, email, telefono]) {
      control.dispose();
    }
    if (guardado != true) return;

    try {
      if (proveedor == null) {
        await proveedoresService.crear(datos);
      } else {
        await proveedoresService.actualizar(proveedor.id, datos);
      }
      if (!mounted) return;
      mostrarAviso(context, 'Proveedor guardado');
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  Future<void> _cambiarEstado(ProveedorOut proveedor) async {
    final activar = !proveedor.activo;
    if (!activar) {
      final confirmado = await confirmar(
        context,
        titulo: 'Dar de baja',
        mensaje: '${proveedor.nombre} tiene ${proveedor.productos} producto(s) y '
            '${proveedor.recepciones} recepcion(es). Dejara de aparecer para nuevas compras.',
        textoConfirmar: 'Dar de baja',
        destructivo: true,
      );
      if (!confirmado) return;
    }

    try {
      await proveedoresService.cambiarEstado(proveedor.id, activar);
      if (!mounted) return;
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final puedeGestionar = context.watch<AuthService>().tienePermiso(['proveedores.gestionar']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Proveedores'),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: puedeGestionar
          ? FloatingActionButton.extended(
              onPressed: () => _abrirFormulario(),
              backgroundColor: Paleta.flame,
              foregroundColor: Paleta.blanco,
              icon: const Icon(Icons.add),
              label: const Text('NUEVO'),
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
                hintText: 'Buscar por nombre, NIT o contacto',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _chipEstado('Todos', null),
                _chipEstado('Activos', true),
                _chipEstado('De baja', false),
              ],
            ),
          ),
          Expanded(
            child: VistaAsincrona(
              cargando: _cargando,
              error: _error,
              alReintentar: _cargar,
              hijo: _proveedores.isEmpty
                  ? const EstadoVacio(mensaje: 'No hay proveedores con ese criterio.')
                  : RefreshIndicator(
                      color: Paleta.flame,
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
                        itemCount: _proveedores.length,
                        separatorBuilder: (contexto, indice) => const SizedBox(height: 10),
                        itemBuilder: (contexto, indice) =>
                            _tarjeta(_proveedores[indice], puedeGestionar),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipEstado(String etiqueta, bool? valor) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(etiqueta),
          selected: _activo == valor,
          selectedColor: Paleta.flame.withValues(alpha: 0.16),
          onSelected: (_) {
            setState(() => _activo = valor);
            _cargar();
          },
        ),
      );

  Widget _tarjeta(ProveedorOut proveedor, bool puedeGestionar) => TarjetaPanel(
        hijo: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    proveedor.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                BadgeEstado(proveedor.activo ? 'ACTIVO' : 'DE BAJA'),
              ],
            ),
            const SizedBox(height: 8),
            if (proveedor.nit != null) FilaDato('NIT', proveedor.nit!),
            if (proveedor.contacto != null) FilaDato('Contacto', proveedor.contacto!),
            if (proveedor.email != null) FilaDato('Email', proveedor.email!),
            if (proveedor.telefono != null) FilaDato('Telefono', proveedor.telefono!),
            FilaDato(
              'Vinculos',
              '${proveedor.productos} producto(s) · ${proveedor.recepciones} recepcion(es)',
            ),
            if (puedeGestionar) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _abrirFormulario(proveedor: proveedor),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('EDITAR'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _cambiarEstado(proveedor),
                    style: TextButton.styleFrom(
                      foregroundColor: proveedor.activo ? Paleta.rojo : Paleta.verde,
                    ),
                    child: Text(proveedor.activo ? 'DAR DE BAJA' : 'REACTIVAR'),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
}

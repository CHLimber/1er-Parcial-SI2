import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/clientes/clientes_service.dart';
import '../core/config.dart';
import '../core/errores.dart';
import '../core/tema.dart';

/// Cartera de clientas de la sucursal (Segundo parcial, PENDIENTES 5.7), espejo de
/// `panel-clientes` de la web: lista con segmento (fijado o sugerido) y ficha editable de esta
/// sucursal.
class PanelClientesPagina extends StatefulWidget {
  const PanelClientesPagina({super.key});

  @override
  State<PanelClientesPagina> createState() => _PanelClientesPaginaState();
}

class _PanelClientesPaginaState extends State<PanelClientesPagina> {
  final _busqueda = TextEditingController();
  String? _segmento;
  List<ClienteTenantOut>? _clientes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _clientes = null;
      _error = null;
    });
    try {
      final q = _busqueda.text.trim();
      final clientes = await clientesService.listar(q: q.isEmpty ? null : q, segmento: _segmento);
      if (mounted) setState(() => _clientes = clientes);
    } catch (error) {
      if (mounted) setState(() => _error = interpretarError(error));
    }
  }

  Future<void> _abrir(ClienteTenantOut cliente) async {
    final guardada = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _FichaClientePagina(cliente: cliente)),
    );
    if (guardada == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final clientes = _clientes;
    return Scaffold(
      appBar: AppBar(title: const Text('Clientas')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            TextField(
              controller: _busqueda,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _cargar(),
              decoration: const InputDecoration(labelText: 'Buscar por nombre o email'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: _segmento,
              decoration: const InputDecoration(labelText: 'Segmento'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                ...segmentos.entries.map((e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value))),
              ],
              onChanged: (v) {
                setState(() => _segmento = v);
                _cargar();
              },
            ),
            const SizedBox(height: 14),
            if (_error != null) MensajeError(_error!, alReintentar: _cargar),
            if (clientes == null && _error == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            if (clientes != null && clientes.isEmpty)
              const EstadoVacio(mensaje: 'No hay clientas en la cartera con esos filtros.'),
            ...?clientes?.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => _abrir(c),
                  child: TarjetaPanel(
                    padding: const EdgeInsets.all(12),
                    hijo: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.w700))),
                            BadgeEstado(segmentos[c.segmento] ?? c.segmento, color: Paleta.gold),
                          ],
                        ),
                        Text(c.email, style: const TextStyle(fontSize: 12, color: Paleta.inkSuave)),
                        const SizedBox(height: 4),
                        Text(
                          '${c.compras} compra(s) · ${formatearPrecio(c.totalComprado)} · ${c.reservas} reserva(s)',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ],
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
}

class _FichaClientePagina extends StatefulWidget {
  const _FichaClientePagina({required this.cliente});

  final ClienteTenantOut cliente;

  @override
  State<_FichaClientePagina> createState() => _FichaClientePaginaState();
}

class _FichaClientePaginaState extends State<_FichaClientePagina> {
  late String? _segmento = widget.cliente.tienePerfil ? widget.cliente.segmento : null;
  late final _talla = TextEditingController(text: widget.cliente.tallaHabitual);
  late final _estilo = TextEditingController(text: widget.cliente.estiloPreferido);
  late final _telefono = TextEditingController(text: widget.cliente.telefonoContacto);
  late final _notas = TextEditingController(text: widget.cliente.notas);
  late bool _whatsapp = widget.cliente.aceptaWhatsapp;
  bool _guardando = false;

  @override
  void dispose() {
    _talla.dispose();
    _estilo.dispose();
    _telefono.dispose();
    _notas.dispose();
    super.dispose();
  }

  String? _texto(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await clientesService.editarPerfil(widget.cliente.usuarioId, {
        'segmento': _segmento,
        'talla_habitual': _texto(_talla),
        'estilo_preferido': _texto(_estilo),
        'telefono_contacto': _texto(_telefono),
        'acepta_whatsapp': _whatsapp,
        'notas': _texto(_notas),
      });
      if (!mounted) return;
      mostrarAviso(context, 'Ficha de ${widget.cliente.nombre} guardada.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cliente;
    final puedeEditar = context.watch<AuthService>().tienePermiso(['clientes.actualizar']);
    return Scaffold(
      appBar: AppBar(title: Text(c.nombre)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          FilaDato('Email', c.email),
          FilaDato('Compras', '${c.compras} · ${formatearPrecio(c.totalComprado)}'),
          FilaDato('Reservas', '${c.reservas}'),
          FilaDato('Segmento sugerido', segmentos[c.segmentoSugerido] ?? c.segmentoSugerido),
          const SizedBox(height: 14),
          DropdownButtonFormField<String?>(
            initialValue: _segmento,
            decoration: const InputDecoration(labelText: 'Segmento'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Automatico (segun historial)')),
              ...segmentos.entries.map((e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value))),
            ],
            onChanged: puedeEditar ? (v) => setState(() => _segmento = v) : null,
          ),
          TextField(controller: _talla, enabled: puedeEditar, decoration: const InputDecoration(labelText: 'Talla habitual')),
          TextField(controller: _estilo, enabled: puedeEditar, decoration: const InputDecoration(labelText: 'Estilo preferido')),
          TextField(
            controller: _telefono,
            enabled: puedeEditar,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Telefono de contacto'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _whatsapp,
            onChanged: puedeEditar ? (v) => setState(() => _whatsapp = v) : null,
            title: const Text('Acepta avisos por WhatsApp'),
          ),
          TextField(
            controller: _notas,
            enabled: puedeEditar,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Notas de la sucursal'),
          ),
          if (puedeEditar)
            ElevatedButton(
              onPressed: _guardando ? null : _guardar,
              child: const Text('GUARDAR FICHA'),
            ),
        ],
      ),
    );
  }
}

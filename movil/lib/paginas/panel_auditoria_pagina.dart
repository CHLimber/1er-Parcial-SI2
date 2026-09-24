import 'package:flutter/material.dart';

import '../compartido/widgets.dart';
import '../core/auditoria/auditoria_service.dart';
import '../core/errores.dart';
import '../core/tema.dart';
import 'mis_reservas_pagina.dart' show fechaLegible;

const _tamanioPagina = 20;

/// Etiquetas legibles para `accion` (espejo de ETIQUETAS_ACCION en
/// `frontend/src/app/pages/panel-auditoria/panel-auditoria.page.ts`).
const Map<String, String> _etiquetasAccion = {
  'CREAR': 'Creacion',
  'ACTUALIZAR': 'Modificacion',
  'ELIMINAR': 'Baja',
  'LOGIN': 'Inicio de sesion',
};

Color _colorAccion(String accion) {
  switch (accion) {
    case 'CREAR':
      return Paleta.verde;
    case 'ELIMINAR':
      return Paleta.rojo;
    case 'LOGIN':
      return Paleta.inkSuave;
    default:
      return Paleta.gold;
  }
}

/// Campos que nunca se muestran en claro, aunque el backend los llegue a mandar algun dia
/// (mismo patron que CAMPOS_SENSIBLES en el frontend web).
final _campoSensible = RegExp(r'password|contrasenia|contrasena|hash|token|secret', caseSensitive: false);
final _pareceFechaHora = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');
final _pareceFecha = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// "precio_base" -> "Precio base": etiqueta legible sin diccionario por entidad.
String _etiquetaCampo(String campo) {
  final texto = campo.replaceAll('_', ' ').trim();
  if (texto.isEmpty) return texto;
  return texto[0].toUpperCase() + texto.substring(1);
}

String _formatearValor(String campo, dynamic valor) {
  if (valor != null && valor != '' && _campoSensible.hasMatch(campo)) return '••••••••';
  if (valor == null || valor == '') return '—';
  if (valor is bool) return valor ? 'Si' : 'No';
  if (valor is num) return '$valor';
  if (valor is String) {
    if (_pareceFechaHora.hasMatch(valor)) {
      final fecha = DateTime.tryParse(valor);
      return fecha == null ? valor : fechaLegible(fecha);
    }
    if (_pareceFecha.hasMatch(valor)) return valor.split('-').reversed.join('/');
    return valor;
  }
  if (valor is List) {
    return valor.isEmpty ? '—' : valor.map((v) => _formatearValor(campo, v)).join(', ');
  }
  if (valor is Map) {
    return valor.entries
        .map((e) => '${_etiquetaCampo(e.key.toString())}: ${_formatearValor(e.key.toString(), e.value)}')
        .join(' · ');
  }
  return '$valor';
}

class _FilaComparacion {
  const _FilaComparacion(this.campo, this.antes, this.despues, this.cambio);

  final String campo;
  final String antes;
  final String despues;
  final bool cambio;
}

List<_FilaComparacion> _filasTotales(AuditoriaOut fila) {
  final antes = fila.datosAntes;
  final despues = fila.datosDespues;
  if (antes == null || despues == null) return const [];
  final claves = {...antes.keys, ...despues.keys};
  return claves
      .map(
        (campo) => _FilaComparacion(
          campo,
          _formatearValor(campo, antes[campo]),
          _formatearValor(campo, despues[campo]),
          antes[campo].toString() != despues[campo].toString(),
        ),
      )
      .toList();
}

/// CU19 - Consultar Bitacora de Auditoria: solo lectura sobre la tabla `auditoria`.
/// Espejo movil de `frontend/src/app/pages/panel-auditoria/`; el permiso `auditoria.leer`
/// (solo ADMIN) ya lo exige `_permisosPorRuta` en `rutas.dart`, aca solo se consulta.
class PanelAuditoriaPagina extends StatefulWidget {
  const PanelAuditoriaPagina({super.key});

  @override
  State<PanelAuditoriaPagina> createState() => _PanelAuditoriaPaginaState();
}

class _PanelAuditoriaPaginaState extends State<PanelAuditoriaPagina> {
  final _entidadIdControlador = TextEditingController();

  List<AuditoriaOut> _items = [];
  List<String> _entidades = [];
  int _total = 0;
  int _pagina = 1;
  bool _cargando = true;
  String? _error;

  String? _entidad;
  String? _accion;
  DateTime? _desde;
  DateTime? _hasta;

  int get _totalPaginas => (_total / _tamanioPagina).ceil().clamp(1, 999999);

  @override
  void initState() {
    super.initState();
    auditoriaService.entidades().then((valores) {
      if (mounted) setState(() => _entidades = valores);
    }).catchError((_) {
      if (mounted) setState(() => _entidades = []);
    });
    _cargar();
  }

  @override
  void dispose() {
    _entidadIdControlador.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final datos = await auditoriaService.listar(
        entidad: _entidad,
        accion: _accion,
        entidadId: _entidadIdControlador.text.trim(),
        desde: _desde,
        hasta: _hasta,
        pagina: _pagina,
        tamanioPagina: _tamanioPagina,
      );
      if (!mounted) return;
      setState(() {
        _items = datos.items;
        _total = datos.total;
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

  void _aplicarFiltro() {
    _pagina = 1;
    _cargar();
  }

  void _limpiarFiltros() {
    setState(() {
      _entidad = null;
      _accion = null;
      _desde = null;
      _hasta = null;
      _entidadIdControlador.clear();
    });
    _aplicarFiltro();
  }

  void _irAPagina(int pagina) {
    if (pagina < 1 || pagina > _totalPaginas) return;
    setState(() => _pagina = pagina);
    _cargar();
  }

  Future<void> _elegirFecha({required bool esDesde}) async {
    final inicial = (esDesde ? _desde : _hasta) ?? DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (elegida == null) return;
    setState(() {
      if (esDesde) {
        _desde = elegida;
      } else {
        _hasta = elegida;
      }
    });
  }

  Future<void> _verDetalle(AuditoriaOut fila) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Paleta.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (contexto) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        builder: (contexto, scroll) => _HojaDetalleAuditoria(fila: fila, scroll: scroll),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auditoria')),
      body: Column(
        children: [
          _panelFiltros(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: MensajeError(_error!, alReintentar: _cargar),
            ),
          Expanded(
            child: VistaAsincrona(
              cargando: _cargando,
              error: null,
              alReintentar: _cargar,
              hijo: _items.isEmpty
                  ? const EstadoVacio(
                      mensaje: 'No hay eventos de auditoria con estos filtros.',
                      icono: Icons.fact_check_outlined,
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            color: Paleta.flame,
                            onRefresh: _cargar,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                              itemCount: _items.length,
                              separatorBuilder: (contexto, indice) => const SizedBox(height: 10),
                              itemBuilder: (contexto, indice) => _tarjeta(_items[indice]),
                            ),
                          ),
                        ),
                        _paginacion(),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelFiltros() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TarjetaPanel(
          padding: const EdgeInsets.all(14),
          hijo: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EtiquetaDato('Filtros'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _entidad,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Entidad'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                        ..._entidades.map(
                          (e) => DropdownMenuItem<String?>(value: e, child: Text(e)),
                        ),
                      ],
                      onChanged: (valor) => setState(() => _entidad = valor),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _accion,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Accion'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                        ..._etiquetasAccion.entries.map(
                          (e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
                        ),
                      ],
                      onChanged: (valor) => setState(() => _accion = valor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _entidadIdControlador,
                decoration: const InputDecoration(
                  labelText: 'ID de entidad',
                  hintText: 'uuid o codigo',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _botonFecha('Desde', _desde, () => _elegirFecha(esDesde: true))),
                  const SizedBox(width: 10),
                  Expanded(child: _botonFecha('Hasta', _hasta, () => _elegirFecha(esDesde: false))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _aplicarFiltro,
                      child: const Text('FILTRAR'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(onPressed: _limpiarFiltros, child: const Text('LIMPIAR')),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _botonFecha(String etiqueta, DateTime? valor, VoidCallback alTocar) => InkWell(
        onTap: alTocar,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: etiqueta,
            suffixIcon: valor == null
                ? const Icon(Icons.calendar_today_outlined, size: 18)
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      if (etiqueta == 'Desde') {
                        _desde = null;
                      } else {
                        _hasta = null;
                      }
                    }),
                  ),
          ),
          child: Text(
            valor == null
                ? 'Sin definir'
                : '${valor.day.toString().padLeft(2, '0')}/${valor.month.toString().padLeft(2, '0')}/${valor.year}',
          ),
        ),
      );

  Widget _tarjeta(AuditoriaOut fila) => TarjetaPanel(
        alTocar: (fila.datosAntes != null || fila.datosDespues != null) ? () => _verDetalle(fila) : null,
        hijo: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    fechaLegible(fila.fecha),
                    style: fuenteMono(fontSize: 12.5, color: Paleta.ink, letterSpacing: 0.3),
                  ),
                ),
                BadgeEstado(
                  _etiquetasAccion[fila.accion] ?? fila.accion,
                  color: _colorAccion(fila.accion),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilaDato('Entidad', fila.entidad),
            FilaDato('ID', fila.entidadId),
            FilaDato(
              'Usuario',
              fila.usuarioNombre == null
                  ? 'Sistema'
                  : '${fila.usuarioNombre}${fila.usuarioEmail != null ? " (${fila.usuarioEmail})" : ""}',
            ),
            if (fila.datosAntes != null || fila.datosDespues != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _verDetalle(fila),
                  icon: const Icon(Icons.visibility_outlined, size: 17),
                  label: const Text('VER CAMBIOS'),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Sin datos de antes/despues registrados',
                  style: const TextStyle(fontSize: 12, color: Paleta.inkSuave),
                ),
              ),
          ],
        ),
      );

  Widget _paginacion() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(
              onPressed: _pagina > 1 ? () => _irAPagina(_pagina - 1) : null,
              child: const Text('ANTERIOR'),
            ),
            Text(
              'Pagina $_pagina de $_totalPaginas · $_total eventos',
              style: const TextStyle(fontSize: 12, color: Paleta.inkSuave),
              textAlign: TextAlign.center,
            ),
            OutlinedButton(
              onPressed: _pagina < _totalPaginas ? () => _irAPagina(_pagina + 1) : null,
              child: const Text('SIGUIENTE'),
            ),
          ],
        ),
      );
}

/// Hoja de detalle de un evento: espejo de la fila expandida en `panel-auditoria.page.html`.
class _HojaDetalleAuditoria extends StatefulWidget {
  const _HojaDetalleAuditoria({required this.fila, required this.scroll});

  final AuditoriaOut fila;
  final ScrollController scroll;

  @override
  State<_HojaDetalleAuditoria> createState() => _HojaDetalleAuditoriaState();
}

class _HojaDetalleAuditoriaState extends State<_HojaDetalleAuditoria> {
  bool _verSinCambios = false;

  @override
  Widget build(BuildContext context) {
    final fila = widget.fila;
    final antes = fila.datosAntes;
    final despues = fila.datosDespues;
    final totales = _filasTotales(fila);
    final cambiadas = totales.where((f) => f.cambio).toList();
    final sinCambio = totales.where((f) => !f.cambio).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Titular('${fila.entidad} · ${_etiquetasAccion[fila.accion] ?? fila.accion}', tamano: 20),
              const SizedBox(height: 4),
              Text(
                '${fechaLegible(fila.fecha)} · ${fila.usuarioNombre ?? "Sistema"}',
                style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scroll,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              if (antes != null && despues != null) ...[
                // ACTUALIZAR (y similares): comparacion campo a campo, primero lo que cambio.
                if (cambiadas.isEmpty)
                  const Text(
                    'No se registraron cambios de valor en este evento.',
                    style: TextStyle(color: Paleta.inkSuave),
                  )
                else ...[
                  Text(
                    'Cambiaron ${cambiadas.length} de ${totales.length} campos:',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ...cambiadas.map(_filaComparacion),
                ],
                if (sinCambio.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => setState(() => _verSinCambios = !_verSinCambios),
                    child: Text(
                      '${_verSinCambios ? "Ocultar" : "Mostrar"} ${sinCambio.length} '
                      'campo${sinCambio.length == 1 ? "" : "s"} sin cambios',
                    ),
                  ),
                  if (_verSinCambios) ...sinCambio.map((f) => _filaComparacion(f, muda: true)),
                ],
              ] else if (despues != null) ...[
                // CREAR: solo hay "despues".
                const Text('Se creo con estos datos:', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...despues.entries.map((e) => _filaValor(e.key, e.value)),
              ] else if (antes != null) ...[
                // ELIMINAR: solo hay "antes".
                const Text(
                  'Tenia estos datos antes de eliminarse:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ...antes.entries.map((e) => _filaValor(e.key, e.value)),
              ],
              const SizedBox(height: 12),
              if (fila.ip != null) FilaDato('IP', fila.ip!),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filaValor(String campo, dynamic valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: FilaDato(_etiquetaCampo(campo), _formatearValor(campo, valor)),
      );

  Widget _filaComparacion(_FilaComparacion f, {bool muda = false}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: muda ? Paleta.paper : Paleta.blanco,
          border: Border.all(color: Paleta.paperLinea),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EtiquetaDato(_etiquetaCampo(f.campo)),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    f.antes,
                    style: TextStyle(
                      color: Paleta.inkSuave,
                      decoration: muda ? null : TextDecoration.lineThrough,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (!muda) const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward, size: 14, color: Paleta.inkSuave),
                ),
                if (!muda)
                  Expanded(
                    child: Text(
                      f.despues,
                      style: const TextStyle(
                        color: Paleta.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
}

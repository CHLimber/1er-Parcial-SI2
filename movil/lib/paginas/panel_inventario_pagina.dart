import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/errores.dart';
import '../core/inventario/inventario_service.dart';
import '../core/sucursales/sucursales_models.dart';
import '../core/sucursales/sucursales_service.dart';
import '../core/tema.dart';
import 'mis_reservas_pagina.dart' show fechaLegible;

/// Ajustes manuales de stock (PENDIENTES.txt 2.6): buscador de variante + kardex +
/// formulario de ajuste, espejo de `frontend/src/app/pages/panel-inventario/`.
///
/// El formulario de ajuste (POST /inventario/ajustes) solo aparece con permiso
/// inventario.actualizar; con solo inventario.leer se puede buscar y ver el kardex.
/// Con sucursales.actualizar aparece el selector de sucursal (como en recepciones);
/// sin ese permiso el backend resuelve sola la sucursal del staff.
class PanelInventarioPagina extends StatefulWidget {
  const PanelInventarioPagina({super.key});

  @override
  State<PanelInventarioPagina> createState() => _PanelInventarioPaginaState();
}

class _PanelInventarioPaginaState extends State<PanelInventarioPagina> {
  final _busqueda = TextEditingController();
  final _cantidadNueva = TextEditingController();
  final _motivo = TextEditingController();

  List<SucursalOut> _sucursales = [];
  String? _sucursalId;

  bool _buscando = false;
  List<VarianteBuscadaOut> _resultados = [];
  String? _errorBusqueda;

  VarianteBuscadaOut? _elegida;
  List<MovimientoKardexOut> _kardex = [];
  bool _cargandoKardex = false;

  bool _guardando = false;
  String? _errorAjuste;

  bool get _eligeSucursal =>
      context.read<AuthService>().tienePermiso(['sucursales.actualizar']);

  @override
  void initState() {
    super.initState();
    // Sin sucursales.actualizar el backend resuelve solo la sucursal del staff (no la
    // conocemos aca, UsuarioOut no la expone) -- no hace falta el selector.
    if (_eligeSucursal) _cargarSucursales();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    _cantidadNueva.dispose();
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _cargarSucursales() async {
    try {
      final sucursales = await sucursalesService.listar();
      if (!mounted) return;
      setState(() {
        _sucursales = sucursales;
        _sucursalId = sucursales.isEmpty ? null : sucursales.first.id;
      });
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  void _cambiarSucursal(String? sucursalId) {
    setState(() {
      _sucursalId = sucursalId;
      _resultados = [];
      _limpiarSeleccion();
    });
  }

  Future<void> _buscar() async {
    final q = _busqueda.text.trim();
    if (q.isEmpty) return;

    setState(() {
      _buscando = true;
      _errorBusqueda = null;
    });
    try {
      final resultados = await inventarioService.buscarVariantes(q, sucursalId: _sucursalId);
      if (!mounted) return;
      setState(() {
        _resultados = resultados;
        _buscando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorBusqueda = interpretarError(error);
        _buscando = false;
      });
    }
  }

  Future<void> _elegir(VarianteBuscadaOut variante) async {
    setState(() {
      _elegida = variante;
      _errorAjuste = null;
      _cantidadNueva.text = '${variante.cantidadFisica}';
      _motivo.clear();
    });
    await _cargarKardex(variante);
  }

  Future<void> _cargarKardex(VarianteBuscadaOut variante) async {
    setState(() => _cargandoKardex = true);
    try {
      final kardex = await inventarioService.kardex(variante.id, sucursalId: variante.sucursalId);
      if (!mounted) return;
      setState(() {
        _kardex = kardex;
        _cargandoKardex = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _kardex = [];
        _cargandoKardex = false;
      });
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  void _limpiarSeleccion() {
    _elegida = null;
    _kardex = [];
    _cantidadNueva.clear();
    _motivo.clear();
    _errorAjuste = null;
  }

  Future<void> _guardarAjuste() async {
    final variante = _elegida;
    if (variante == null) return;

    final cantidad = int.tryParse(_cantidadNueva.text.trim());
    if (cantidad == null || cantidad <= 0) {
      setState(() => _errorAjuste = 'La cantidad fisica nueva tiene que ser mayor a cero.');
      return;
    }
    final motivo = _motivo.text.trim();
    if (motivo.length < 3) {
      setState(() => _errorAjuste = 'Conta el motivo del ajuste (minimo 3 caracteres).');
      return;
    }

    setState(() {
      _guardando = true;
      _errorAjuste = null;
    });
    try {
      final resultado = await inventarioService.ajustar(
        sucursalId: variante.sucursalId,
        varianteId: variante.id,
        cantidadFisicaNueva: cantidad,
        motivo: motivo,
      );
      if (!mounted) return;

      final actualizada = VarianteBuscadaOut(
        id: variante.id,
        sku: variante.sku,
        producto: variante.producto,
        talla: variante.talla,
        color: variante.color,
        codigoHex: variante.codigoHex,
        sucursalId: variante.sucursalId,
        sucursal: variante.sucursal,
        cantidadFisica: resultado.saldoNuevo,
        cantidadReservada: variante.cantidadReservada,
        disponible: resultado.saldoNuevo - variante.cantidadReservada,
      );
      setState(() {
        _guardando = false;
        _elegida = actualizada;
        _cantidadNueva.text = '${resultado.saldoNuevo}';
        _motivo.clear();
        _resultados = _resultados
            .map((fila) => fila.id == actualizada.id ? actualizada : fila)
            .toList();
      });
      mostrarAviso(
        context,
        'Ajuste registrado: ${resultado.saldoAnterior} -> ${resultado.saldoNuevo} unidades',
      );
      await _cargarKardex(actualizada);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _errorAjuste = interpretarError(error);
      });
    }
  }

  static const _etiquetasMovimiento = {
    'ENTRADA': 'Entrada',
    'SALIDA': 'Salida',
    'RESERVA': 'Reserva',
    'LIBERACION': 'Liberacion',
    'AJUSTE': 'Ajuste',
    'TRASPASO_SALIDA': 'Traspaso (salida)',
    'TRASPASO_ENTRADA': 'Traspaso (entrada)',
  };

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final puedeAjustar = auth.tienePermiso(['inventario.actualizar']);
    final eligeSucursal = _eligeSucursal;
    final variante = _elegida;

    return Scaffold(
      appBar: AppBar(title: const Text('Inventario')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
        children: [
          const Text(
            'Ajusta el stock fisico cuando el conteo no coincide con el sistema. Cada '
            'ajuste queda en el kardex, no se puede editar ni borrar.',
            style: TextStyle(color: Paleta.inkSuave, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (eligeSucursal) ...[
            DropdownButtonFormField<String>(
              initialValue: _sucursalId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Sucursal'),
              items: _sucursales
                  .map((s) => DropdownMenuItem(value: s.id, child: Text(s.nombre)))
                  .toList(),
              onChanged: _cambiarSucursal,
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _busqueda,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _buscar(),
            decoration: InputDecoration(
              labelText: 'SKU, codigo de barras o nombre',
              suffixIcon: IconButton(
                icon: _buscando
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                onPressed: _buscando ? null : _buscar,
              ),
            ),
          ),
          if (_errorBusqueda != null) ...[
            const SizedBox(height: 10),
            MensajeError(_errorBusqueda!, alReintentar: _buscar),
          ],
          const SizedBox(height: 14),
          if (_resultados.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: EstadoVacio(
                mensaje: 'Busca una prenda por SKU, codigo de barras o nombre para ver su stock.',
                icono: Icons.inventory_2_outlined,
              ),
            )
          else
            ..._resultados.map(
              (fila) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TarjetaPanel(
                  alTocar: () => _elegir(fila),
                  hijo: Row(
                    children: [
                      Icon(
                        variante?.id == fila.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: Paleta.flame,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    fila.producto,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Text(fila.sku, style: fuenteMono(fontSize: 11, color: Paleta.inkSuave)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _colorDeHex(fila.codigoHex),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Paleta.paperLinea),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${fila.talla} . ${fila.color} . ${fila.sucursal}',
                                    style: const TextStyle(fontSize: 12, color: Paleta.inkSuave),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Fisico ${fila.cantidadFisica} . Reservado ${fila.cantidadReservada} . '
                              'Disponible ${fila.disponible}',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (variante != null) ...[
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 12),
            Text(variante.producto, style: fuenteDisplay(fontSize: 20, color: Paleta.ink)),
            const SizedBox(height: 4),
            Text(
              '${variante.sku} . ${variante.talla} . ${variante.color} . ${variante.sucursal}',
              style: const TextStyle(color: Paleta.inkSuave),
            ),
            const SizedBox(height: 8),
            Text(
              'Fisico actual ${variante.cantidadFisica} . Reservado ${variante.cantidadReservada} . '
              'Disponible ${variante.disponible}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (puedeAjustar) ...[
              const SizedBox(height: 18),
              const EtiquetaDato('Registrar ajuste'),
              const SizedBox(height: 10),
              TextField(
                controller: _cantidadNueva,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cantidad fisica nueva'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _motivo,
                decoration: const InputDecoration(
                  labelText: 'Motivo del ajuste',
                  hintText: 'Conteo fisico, prenda danada, robo...',
                ),
              ),
              if (_errorAjuste != null) ...[
                const SizedBox(height: 10),
                Text(_errorAjuste!, style: const TextStyle(color: Paleta.rojo)),
              ],
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: _guardando ? null : _guardarAjuste,
                child: Text(_guardando ? 'GUARDANDO...' : 'GUARDAR AJUSTE'),
              ),
            ],
            const SizedBox(height: 20),
            const EtiquetaDato('Kardex'),
            const SizedBox(height: 8),
            if (_cargandoKardex)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_kardex.isEmpty)
              const EstadoVacio(
                mensaje: 'Sin movimientos registrados para esta variante en esta sucursal.',
                icono: Icons.history,
              )
            else
              ..._kardex.map(
                (movimiento) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TarjetaPanel(
                    padding: const EdgeInsets.all(12),
                    hijo: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _etiquetasMovimiento[movimiento.tipo] ?? movimiento.tipo,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(
                              fechaLegible(movimiento.fecha),
                              style: const TextStyle(fontSize: 11, color: Paleta.inkSuave),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cantidad ${movimiento.cantidad} . saldo ${movimiento.saldoAnterior} -> '
                          '${movimiento.saldoNuevo}',
                          style: fuenteMono(fontSize: 12, fontWeight: FontWeight.w500, color: Paleta.inkSuave),
                        ),
                        if (movimiento.motivo != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            movimiento.motivo!,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ],
                        if (movimiento.usuario != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            movimiento.usuario!,
                            style: const TextStyle(fontSize: 11, color: Paleta.inkSuave),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Color _colorDeHex(String hex) {
    final limpio = hex.replaceAll('#', '');
    final valor = int.tryParse('FF$limpio', radix: 16);
    return valor == null ? Paleta.paperLinea : Color(valor);
  }
}

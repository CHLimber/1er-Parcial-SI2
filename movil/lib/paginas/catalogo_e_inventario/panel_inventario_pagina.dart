import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../compartido/widgets.dart';
import '../../core/acceso_y_organizacion/auth/auth_service.dart';
import '../../core/errores.dart';
import '../../core/catalogo_e_inventario/inventario/inventario_service.dart';
import '../../core/acceso_y_organizacion/sucursales/sucursales_models.dart';
import '../../core/acceso_y_organizacion/sucursales/sucursales_service.dart';
import '../../core/tema.dart';
import '../operacion_comercial/mis_reservas_pagina.dart' show fechaLegible;

/// CU10 - Gestionar inventario: indicadores de la sucursal, listado con alertas de stock,
/// buscador, kardex y ajustes manuales (PENDIENTES.txt 2.6). Espejo de
/// `frontend/src/app/pages/catalogo-e-inventario/panel-inventario/`.
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

  /// Indicadores de la sucursal (GET /inventario/resumen); null mientras carga o si falla.
  ResumenInventarioOut? _resumen;

  /// Filtro rapido del listado: todas, con stock bajo o agotadas.
  AlertaInventario? _alerta;

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
    if (_eligeSucursal) {
      _cargarSucursales();
    } else {
      _cargarTodo();
    }
    _cantidadNueva.addListener(() => setState(() {}));
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
      await _cargarTodo();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  void _cambiarSucursal(String? sucursalId) {
    setState(() {
      _sucursalId = sucursalId;
      _limpiarSeleccion();
    });
    _cargarTodo();
  }

  /// Indicadores + listado inicial (lo que mas necesita atencion), sin tener que buscar primero.
  Future<void> _cargarTodo() async {
    _cargarResumen();
    await _buscar();
  }

  Future<void> _cargarResumen() async {
    try {
      final resumen = await inventarioService.resumen(sucursalId: _sucursalId);
      if (mounted) setState(() => _resumen = resumen);
    } catch (_) {
      if (mounted) setState(() => _resumen = null);
    }
  }

  void _filtrarPor(AlertaInventario? alerta) {
    setState(() => _alerta = alerta);
    _buscar();
  }

  Future<void> _buscar() async {
    final q = _busqueda.text.trim();

    setState(() {
      _buscando = true;
      _errorBusqueda = null;
    });
    try {
      final resultados = await inventarioService.buscarVariantes(q, sucursalId: _sucursalId, alerta: _alerta);
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
    // 0 vale: es el recuento que registra que se perdio o se danio la ultima unidad
    if (cantidad == null || cantidad < 0) {
      setState(() => _errorAjuste = 'La cantidad fisica nueva no puede ser negativa.');
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
        stockMinimo: variante.stockMinimo,
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
      _cargarResumen();
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
    'TRASPASO_SAL': 'Traspaso (salida)',
    'TRASPASO_ENT': 'Traspaso (entrada)',
    'DEVOLUCION': 'Devolución',
    'MERMA': 'Merma',
  };

  static const _etiquetasDocumento = {
    'RECEPCION': 'Recepción de mercadería',
    'VENTA': 'Venta',
    'RESERVA': 'Reserva',
    'TRASPASO': 'Traspaso',
    'DEVOLUCION': 'Devolución',
  };

  /// Estado de una prenda para la insignia del listado.
  (String, Color) _estadoStock(VarianteBuscadaOut v) {
    if (v.disponible <= 0) return ('Agotada', Paleta.rojo);
    if (v.disponible <= v.stockMinimo) return ('Stock bajo', Paleta.gold);
    return ('Disponible', Paleta.verde);
  }

  /// Cuanto cambia el fisico si se guarda lo que se escribio (para avisar antes de guardar).
  int? get _variacionAjuste {
    final v = _elegida;
    final nueva = int.tryParse(_cantidadNueva.text.trim());
    if (v == null || nueva == null) return null;
    return nueva - v.cantidadFisica;
  }

  String get _tituloListado {
    if (_alerta == AlertaInventario.agotadas) return 'Prendas agotadas';
    if (_alerta == AlertaInventario.bajo) return 'Prendas con stock bajo';
    return _busqueda.text.trim().isEmpty ? 'Primero lo que hay que mirar' : 'Resultados';
  }

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
            'Existencias por sucursal: qué hay, qué está comprometido y qué hay que reponer. '
            'Cada ajuste queda en el kardex, que no se edita ni se borra.',
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
          if (_resumen case final resumen?) ...[_indicadores(resumen), const SizedBox(height: 14)],
          TextField(
            controller: _busqueda,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _buscar(),
            decoration: InputDecoration(
              labelText: 'Buscar prenda',
              hintText: 'SKU, código de barras o nombre',
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
          const SizedBox(height: 16),
          Text('$_tituloListado (${_resultados.length})', style: fuenteDisplay(fontSize: 18)),
          if (_busqueda.text.trim().isEmpty && _alerta == null) ...[
            const SizedBox(height: 2),
            const Text(
              'Ordenadas de menos a más disponible. Buscá para ver cualquier otra prenda.',
              style: TextStyle(color: Paleta.inkSuave, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 10),
          if (_resultados.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: EstadoVacio(
                mensaje: _buscando
                    ? 'Cargando…'
                    : _alerta != null || _busqueda.text.trim().isNotEmpty
                        ? 'Ninguna prenda coincide con este filtro.'
                        : 'Todavía no hay prendas con existencias en esta sucursal.',
                icono: Icons.inventory_2_outlined,
              ),
            )
          else
            ..._resultados.map(
              (fila) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _tarjetaPrenda(fila)),
            ),
          if (variante != null) ...[
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 12),
            _ficha(variante, puedeAjustar),
          ] else if (_resultados.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Elegí una prenda de la lista para ver su stock, su historial y corregirlo si hace falta.',
              style: TextStyle(color: Paleta.inkSuave, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }

  /// Cuatro indicadores de la sucursal; "Stock bajo" y "Agotadas" filtran el listado al tocarlos.
  Widget _indicadores(ResumenInventarioOut r) {
    Widget indicador({
      required String etiqueta,
      required int valor,
      required String detalle,
      AlertaInventario? filtro,
      bool alerta = false,
    }) {
      final activo = filtro != null && _alerta == filtro;
      final resaltado = alerta || activo;
      return Material(
        color: activo ? Paleta.flame.withValues(alpha: 0.08) : Paleta.blanco,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: resaltado ? Paleta.flame : Paleta.paperLinea, width: activo ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: filtro == null ? null : () => _filtrarPor(activo ? null : filtro),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EtiquetaDato(etiqueta, color: alerta ? Paleta.flame : null),
                const SizedBox(height: 4),
                Text('$valor', style: fuenteDisplay(fontSize: 28, color: alerta ? Paleta.flame : Paleta.ink)),
                const SizedBox(height: 2),
                Text(detalle, style: const TextStyle(color: Paleta.inkSuave, fontSize: 11.5, height: 1.3)),
              ],
            ),
          ),
        ),
      );
    }

    final tarjetas = [
      indicador(
        etiqueta: 'En ${r.sucursal}',
        valor: r.unidadesFisicas,
        detalle: 'unidades físicas · ${r.variantes} prendas (talla y color)',
      ),
      indicador(
        etiqueta: 'Disponible',
        valor: r.unidadesDisponibles,
        detalle: '${r.unidadesReservadas} comprometidas en reservas',
      ),
      indicador(
        etiqueta: 'Stock bajo',
        valor: r.stockBajo,
        detalle: 'en o bajo su mínimo · tocá para filtrar',
        filtro: AlertaInventario.bajo,
        alerta: r.stockBajo > 0,
      ),
      indicador(
        etiqueta: 'Agotadas',
        valor: r.agotadas,
        detalle: 'sin nada disponible · tocá para filtrar',
        filtro: AlertaInventario.agotadas,
        alerta: r.agotadas > 0,
      ),
    ];
    return Column(
      children: [
        for (var fila = 0; fila < 2; fila++) ...[
          if (fila > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tarjetas[fila * 2]),
                const SizedBox(width: 10),
                Expanded(child: tarjetas[fila * 2 + 1]),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _tarjetaPrenda(VarianteBuscadaOut fila) {
    final (estado, colorEstado) = _estadoStock(fila);
    final elegida = _elegida?.id == fila.id;
    return TarjetaPanel(
      alTocar: () => _elegir(fila),
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(fila.sku, style: fuenteMono(fontSize: 11, color: Paleta.inkSuave))),
              BadgeEstado(estado, color: colorEstado),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            fila.producto,
            style: TextStyle(fontWeight: FontWeight.w700, color: elegida ? Paleta.flame : Paleta.ink),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _punto(fila.codigoHex),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Talla ${fila.talla} · ${fila.color}',
                  style: const TextStyle(fontSize: 12, color: Paleta.inkSuave),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${fila.disponible} disponibles · ${fila.cantidadFisica} físicas'
            '${fila.cantidadReservada > 0 ? ' · ${fila.cantidadReservada} reservadas' : ''}'
            '${fila.stockMinimo > 0 ? ' · mínimo ${fila.stockMinimo}' : ''}',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _punto(String hex) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: _colorDeHex(hex),
          shape: BoxShape.circle,
          border: Border.all(color: Paleta.paperLinea),
        ),
      );

  Widget _cifra(String etiqueta, int valor, String ayuda, {bool destacada = false}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: destacada ? Paleta.ink : Paleta.blanco,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: destacada ? Paleta.ink : Paleta.paperLinea),
          ),
          child: Column(
            children: [
              Text('$valor', style: fuenteDisplay(fontSize: 26, color: destacada ? Paleta.paper : Paleta.ink)),
              Text(
                etiqueta.toUpperCase(),
                style: fuenteMono(fontSize: 10, color: destacada ? Paleta.gold : Paleta.inkSuave),
              ),
              const SizedBox(height: 2),
              Text(
                ayuda,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: destacada ? Paleta.paper : Paleta.inkSuave),
              ),
            ],
          ),
        ),
      );

  /// Ficha de la prenda elegida: cifras, ajuste con previa y kardex.
  Widget _ficha(VarianteBuscadaOut variante, bool puedeAjustar) {
    final variacion = _variacionAjuste;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(variante.producto, style: fuenteDisplay(fontSize: 20, color: Paleta.ink)),
        const SizedBox(height: 4),
        Row(
          children: [
            _punto(variante.codigoHex),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Talla ${variante.talla} · ${variante.color} · ${variante.sku} · ${variante.sucursal}',
                style: const TextStyle(color: Paleta.inkSuave),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _cifra('Físico', variante.cantidadFisica, 'en el estante'),
            const SizedBox(width: 8),
            _cifra('Reservado', variante.cantidadReservada, 'apartado'),
            const SizedBox(width: 8),
            _cifra('Disponible', variante.disponible, 'se vende hoy', destacada: true),
          ],
        ),
        if (puedeAjustar) ...[
          const SizedBox(height: 18),
          const EtiquetaDato('Corregir el stock físico'),
          const SizedBox(height: 4),
          const Text(
            'Escribí cuántas unidades contaste. El sistema registra la diferencia en el kardex con el motivo.',
            style: TextStyle(color: Paleta.inkSuave, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _cantidadNueva,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Cantidad física contada'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _motivo,
            decoration: const InputDecoration(
              labelText: 'Motivo del ajuste',
              hintText: 'Conteo físico, prenda dañada, robo…',
            ),
          ),
          if (variacion != null && variacion != 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (variacion < 0 ? Paleta.rojo : Paleta.verde).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'El físico pasará de ${variante.cantidadFisica} a ${_cantidadNueva.text.trim()} '
                '(${variacion > 0 ? '+' : ''}$variacion).',
                style: TextStyle(fontWeight: FontWeight.w600, color: variacion < 0 ? Paleta.rojo : Paleta.verde),
              ),
            ),
          ] else if (variacion == 0) ...[
            const SizedBox(height: 10),
            const Text(
              'La cantidad es la misma que hay hoy: no habría nada que ajustar.',
              style: TextStyle(color: Paleta.inkSuave, fontSize: 12.5),
            ),
          ],
          if (_errorAjuste != null) ...[
            const SizedBox(height: 10),
            Text(_errorAjuste!, style: const TextStyle(color: Paleta.rojo)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _guardando || variacion == 0 ? null : _guardarAjuste,
                  child: Text(_guardando ? 'GUARDANDO...' : 'GUARDAR AJUSTE'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => setState(_limpiarSeleccion),
                child: const Text('CERRAR'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        const EtiquetaDato('Historial de movimientos (kardex)'),
        const SizedBox(height: 4),
        const Text(
          'Del más reciente al más antiguo. «Antes» y «Después» son el stock en ese momento.',
          style: TextStyle(color: Paleta.inkSuave, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        if (_cargandoKardex)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_kardex.isEmpty)
          const EstadoVacio(
            mensaje: 'Sin movimientos registrados para esta prenda en esta sucursal.',
            icono: Icons.history,
          )
        else
          ..._kardex.map(_tarjetaMovimiento),
      ],
    );
  }

  Widget _tarjetaMovimiento(MovimientoKardexOut m) {
    final variacion = m.saldoNuevo - m.saldoAnterior;
    final colorVariacion = variacion > 0 ? Paleta.verde : (variacion < 0 ? Paleta.rojo : Paleta.inkSuave);
    return Padding(
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
                    _etiquetasMovimiento[m.tipo] ?? m.tipo,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${variacion > 0 ? '+' : ''}$variacion',
                  style: fuenteMono(fontSize: 14, color: colorVariacion),
                ),
              ],
            ),
            if (m.documentoTipo != null)
              Text(
                _etiquetasDocumento[m.documentoTipo] ?? m.documentoTipo!,
                style: const TextStyle(fontSize: 12, color: Paleta.inkSuave),
              ),
            const SizedBox(height: 4),
            Text(
              'Antes ${m.saldoAnterior} → Después ${m.saldoNuevo} · ${fechaLegible(m.fecha)}',
              style: fuenteMono(fontSize: 11.5, fontWeight: FontWeight.w500, color: Paleta.inkSuave),
            ),
            if (m.motivo != null) ...[
              const SizedBox(height: 3),
              Text(m.motivo!, style: const TextStyle(fontSize: 12.5)),
            ],
            if (m.usuario != null) ...[
              const SizedBox(height: 3),
              Text(m.usuario!, style: const TextStyle(fontSize: 11, color: Paleta.inkSuave)),
            ],
          ],
        ),
      ),
    );
  }

  Color _colorDeHex(String hex) {
    final limpio = hex.replaceAll('#', '');
    final valor = int.tryParse('FF$limpio', radix: 16);
    return valor == null ? Paleta.paperLinea : Color(valor);
  }
}

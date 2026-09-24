import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../compartido/widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/catalogo/catalogo_models.dart';
import '../core/catalogo/catalogo_service.dart';
import '../core/config.dart';
import '../core/errores.dart';
import '../core/reportes/reportes_models.dart';
import '../core/reportes/reportes_service.dart';
import '../core/sucursales/sucursales_models.dart';
import '../core/sucursales/sucursales_service.dart';
import '../core/tema.dart';

/// CU15 - Consultar Reportes e Indicadores, espejo movil (acotado para telefono) de
/// `frontend/src/app/pages/panel-reportes`. 4 pestanas -- Indicadores, Estaticos, Dinamicos
/// y Reporte con IA -- todas de solo lectura (permiso unico `reportes.leer`, ADMIN y
/// ENCARGADO). Sin graficos (no se agrego dependencia de charts) ni exportacion PDF/Excel:
/// eso queda en PENDIENTES.txt, la web ya lo tiene. Un ENCARGADO solo ve su sucursal (el
/// backend la resuelve solo, el filtro de sucursal ni se muestra); un ADMIN
/// (`sucursales.actualizar`) puede elegir cualquiera o dejarlo vacio para la cadena
/// completa, igual criterio que `panel-reportes.page.ts`.
class PanelReportesPagina extends StatefulWidget {
  const PanelReportesPagina({super.key});

  @override
  State<PanelReportesPagina> createState() => _PanelReportesPaginaState();
}

class _PanelReportesPaginaState extends State<PanelReportesPagina> {
  List<SucursalOut> _sucursales = [];
  List<CategoriaOut> _categorias = [];

  @override
  void initState() {
    super.initState();
    _cargarReferencias();
  }

  /// Referencias para poblar los dropdowns de sucursal/categoria. Se reusan los servicios
  /// publicos que ya existen (CU04 y CU03) en vez de duplicar un fetch admin -- mismo
  /// criterio que la web con `CatalogoService.obtenerFiltros()` (PENDIENTES 2.5.1). Si
  /// fallan, los dropdowns quedan sin opciones pero el resto de la pantalla sigue andando.
  Future<void> _cargarReferencias() async {
    try {
      final sucursales = await sucursalesService.listar();
      final filtros = await catalogoService.obtenerFiltros();
      if (!mounted) return;
      setState(() {
        _sucursales = sucursales;
        _categorias = filtros.categorias;
      });
    } catch (_) {
      // silencioso a proposito: no bloquea la pantalla por un dropdown auxiliar.
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final puedeElegirSucursal = auth.tienePermiso(['sucursales.actualizar']);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reportes'),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Paleta.paper,
            unselectedLabelColor: Paleta.paperLinea,
            indicatorColor: Paleta.flame,
            tabs: [
              Tab(text: 'INDICADORES'),
              Tab(text: 'ESTATICOS'),
              Tab(text: 'DINAMICOS'),
              Tab(text: 'REPORTE CON IA'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _PestanaIndicadores(sucursales: _sucursales, puedeElegirSucursal: puedeElegirSucursal),
            _PestanaEstaticos(
              sucursales: _sucursales,
              categorias: _categorias,
              puedeElegirSucursal: puedeElegirSucursal,
            ),
            _PestanaDinamicos(
              sucursales: _sucursales,
              categorias: _categorias,
              puedeElegirSucursal: puedeElegirSucursal,
            ),
            const _PestanaIa(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------
//  Filtros comunes: sucursal (solo si puede elegirla), fecha desde/hasta.
// ---------------------------------------------------------------------------------------

class _SelectorSucursal extends StatelessWidget {
  const _SelectorSucursal({
    required this.sucursales,
    required this.valor,
    required this.alCambiar,
  });

  final List<SucursalOut> sucursales;
  final String? valor;
  final ValueChanged<String?> alCambiar;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String?>(
        initialValue: valor,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Sucursal'),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('Toda la cadena')),
          ...sucursales.map(
            (s) => DropdownMenuItem<String?>(value: s.id, child: Text(s.nombre, overflow: TextOverflow.ellipsis)),
          ),
        ],
        onChanged: alCambiar,
      );
}

class _SelectorCategoria extends StatelessWidget {
  const _SelectorCategoria({
    required this.categorias,
    required this.valor,
    required this.alCambiar,
  });

  final List<CategoriaOut> categorias;
  final String? valor;
  final ValueChanged<String?> alCambiar;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String?>(
        initialValue: valor,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Categoria'),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
          ...categorias.map(
            (c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.nombre, overflow: TextOverflow.ellipsis)),
          ),
        ],
        onChanged: alCambiar,
      );
}

class _SelectorFecha extends StatelessWidget {
  const _SelectorFecha({required this.etiqueta, required this.valor, required this.alCambiar});

  final String etiqueta;
  final DateTime? valor;
  final ValueChanged<DateTime?> alCambiar;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () async {
          final elegida = await showDatePicker(
            context: context,
            initialDate: valor ?? DateTime.now(),
            firstDate: DateTime(2024),
            lastDate: DateTime.now().add(const Duration(days: 1)),
          );
          if (elegida != null) alCambiar(elegida);
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: etiqueta),
          child: Text(
            valor == null ? 'Ultimos 30 dias' : valor!.toIso8601String().split('T').first,
          ),
        ),
      );
}

/// Tarjeta de KPI simple (sin canvas): etiqueta arriba, valor grande abajo.
class _TarjetaKpi extends StatelessWidget {
  const _TarjetaKpi({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 156,
        child: TarjetaPanel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          hijo: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              EtiquetaDato(etiqueta),
              const SizedBox(height: 6),
              Text(
                valor,
                style: fuenteDisplay(fontSize: 21, color: Paleta.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------------------------------
//  Pestana 1: Indicadores (KPIs del periodo)
// ---------------------------------------------------------------------------------------

class _PestanaIndicadores extends StatefulWidget {
  const _PestanaIndicadores({required this.sucursales, required this.puedeElegirSucursal});

  final List<SucursalOut> sucursales;
  final bool puedeElegirSucursal;

  @override
  State<_PestanaIndicadores> createState() => _PestanaIndicadoresState();
}

class _PestanaIndicadoresState extends State<_PestanaIndicadores> {
  DateTime? _desde;
  DateTime? _hasta;
  String? _sucursalId;
  bool _cargando = true;
  String? _error;
  IndicadoresOut? _indicadores;

  @override
  void initState() {
    super.initState();
    _consultar();
  }

  Future<void> _consultar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final indicadores = await reportesService.obtenerIndicadores(
        desde: _desde,
        hasta: _hasta,
        sucursalId: _sucursalId,
      );
      if (!mounted) return;
      setState(() {
        _indicadores = indicadores;
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

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
        children: [
          Row(
            children: [
              Expanded(
                child: _SelectorFecha(
                  etiqueta: 'Desde',
                  valor: _desde,
                  alCambiar: (v) => setState(() => _desde = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SelectorFecha(
                  etiqueta: 'Hasta',
                  valor: _hasta,
                  alCambiar: (v) => setState(() => _hasta = v),
                ),
              ),
            ],
          ),
          if (widget.puedeElegirSucursal) ...[
            const SizedBox(height: 10),
            _SelectorSucursal(
              sucursales: widget.sucursales,
              valor: _sucursalId,
              alCambiar: (v) => setState(() => _sucursalId = v),
            ),
          ],
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _cargando ? null : _consultar, child: const Text('CONSULTAR')),
          const SizedBox(height: 18),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            MensajeError(_error!, alReintentar: _consultar)
          else if (_indicadores != null)
            _grillaKpis(_indicadores!),
        ],
      );

  Widget _grillaKpis(IndicadoresOut d) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _TarjetaKpi(etiqueta: 'Ventas', valor: '${d.ventasCantidad}'),
          _TarjetaKpi(etiqueta: 'Monto vendido', valor: formatearPrecio(d.ventasMonto)),
          _TarjetaKpi(etiqueta: 'Ticket promedio', valor: formatearPrecio(d.ticketPromedio)),
          _TarjetaKpi(etiqueta: 'Reservas creadas', valor: '${d.reservasCreadas}'),
          _TarjetaKpi(etiqueta: 'Reservas convertidas', valor: '${d.reservasConvertidas}'),
          _TarjetaKpi(etiqueta: 'Conversion', valor: '${d.tasaConversionReservas}%'),
          _TarjetaKpi(etiqueta: 'Stock bajo', valor: '${d.variantesStockBajo}'),
          _TarjetaKpi(etiqueta: 'Agotadas', valor: '${d.variantesAgotadas}'),
          _TarjetaKpi(etiqueta: 'Envios con flete', valor: '${d.enviosCantidad}'),
          _TarjetaKpi(etiqueta: 'Cobrado en flete', valor: formatearPrecio(d.enviosMonto)),
        ],
      );
}

// ---------------------------------------------------------------------------------------
//  Pestana 2: Estaticos (foto del estado actual, un tipo a la vez)
// ---------------------------------------------------------------------------------------

enum _TipoEstatico {
  stock,
  reservas,
  envios,
  sinMovimiento,
  topClientes,
  ocupacionCajas,
  recepcionesPendientes,
  existencias,
}

extension on _TipoEstatico {
  String get etiqueta => switch (this) {
        _TipoEstatico.stock => 'Stock por sucursal',
        _TipoEstatico.reservas => 'Reservas por estado',
        _TipoEstatico.envios => 'Envios por estado',
        _TipoEstatico.sinMovimiento => 'Productos sin movimiento',
        _TipoEstatico.topClientes => 'Top clientes',
        _TipoEstatico.ocupacionCajas => 'Ocupacion de cajas',
        _TipoEstatico.recepcionesPendientes => 'Recepciones pendientes',
        _TipoEstatico.existencias => 'Existencias (consolidado)',
      };
}

class _PestanaEstaticos extends StatefulWidget {
  const _PestanaEstaticos({
    required this.sucursales,
    required this.categorias,
    required this.puedeElegirSucursal,
  });

  final List<SucursalOut> sucursales;
  final List<CategoriaOut> categorias;
  final bool puedeElegirSucursal;

  @override
  State<_PestanaEstaticos> createState() => _PestanaEstaticosState();
}

class _PestanaEstaticosState extends State<_PestanaEstaticos> {
  _TipoEstatico _tipo = _TipoEstatico.stock;
  String? _sucursalId;
  String? _categoriaId;
  final _busqueda = TextEditingController();
  String? _situacion;

  bool _cargando = true;
  String? _error;
  List<dynamic> _items = [];
  ResumenExistenciasOut? _resumen;

  @override
  void initState() {
    super.initState();
    _consultar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _consultar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      List<dynamic> items;
      ResumenExistenciasOut? resumen;
      switch (_tipo) {
        case _TipoEstatico.stock:
          items = await reportesService.listarStockPorSucursal(sucursalId: _sucursalId);
        case _TipoEstatico.reservas:
          items = await reportesService.listarReservasPorEstado(sucursalId: _sucursalId);
        case _TipoEstatico.envios:
          items = await reportesService.listarEnviosPorEstado(sucursalId: _sucursalId);
        case _TipoEstatico.sinMovimiento:
          items = await reportesService.listarProductosSinMovimiento(sucursalId: _sucursalId, limite: 50);
        case _TipoEstatico.topClientes:
          items = await reportesService.listarTopClientes(sucursalId: _sucursalId, limite: 10);
        case _TipoEstatico.ocupacionCajas:
          items = await reportesService.listarOcupacionCajas(sucursalId: _sucursalId);
        case _TipoEstatico.recepcionesPendientes:
          items = await reportesService.listarRecepcionesPendientes(sucursalId: _sucursalId);
        case _TipoEstatico.existencias:
          final pagina = await reportesService.listarExistencias(
            sucursalId: _sucursalId,
            categoriaId: _categoriaId,
            busqueda: _busqueda.text,
            situacion: _situacion,
          );
          items = pagina.items;
          resumen = pagina.resumen;
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _resumen = resumen;
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

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
        children: [
          DropdownButtonFormField<_TipoEstatico>(
            initialValue: _tipo,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tipo de consulta'),
            items: _TipoEstatico.values
                .map((t) => DropdownMenuItem(value: t, child: Text(t.etiqueta)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _tipo = v);
              _consultar();
            },
          ),
          if (widget.puedeElegirSucursal) ...[
            const SizedBox(height: 10),
            _SelectorSucursal(
              sucursales: widget.sucursales,
              valor: _sucursalId,
              alCambiar: (v) => setState(() => _sucursalId = v),
            ),
          ],
          if (_tipo == _TipoEstatico.existencias) ...[
            const SizedBox(height: 10),
            _SelectorCategoria(
              categorias: widget.categorias,
              valor: _categoriaId,
              alCambiar: (v) => setState(() => _categoriaId = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _busqueda,
              decoration: const InputDecoration(labelText: 'Buscar por prenda o SKU'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                _chipSituacion('Todas', null),
                _chipSituacion('Disponible', 'DISPONIBLE'),
                _chipSituacion('Reservada', 'RESERVADA'),
                _chipSituacion('Por ingresar', 'PROXIMA_A_INGRESAR'),
                _chipSituacion('Agotada', 'AGOTADA'),
              ],
            ),
          ],
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _cargando ? null : _consultar, child: const Text('CONSULTAR')),
          const SizedBox(height: 18),
          if (_resumen != null) _tarjetaResumenExistencias(_resumen!),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            MensajeError(_error!, alReintentar: _consultar)
          else if (_items.isEmpty)
            const EstadoVacio(mensaje: 'Sin resultados para ese filtro.')
          else
            ..._items.map(_tarjetaItem),
        ],
      );

  Widget _chipSituacion(String etiqueta, String? valor) => FilterChip(
        label: Text(etiqueta),
        selected: _situacion == valor,
        selectedColor: Paleta.flame.withValues(alpha: 0.16),
        onSelected: (_) => setState(() => _situacion = valor),
      );

  Widget _tarjetaResumenExistencias(ResumenExistenciasOut r) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _TarjetaKpi(etiqueta: 'Variantes', valor: '${r.variantesTotal}'),
            _TarjetaKpi(etiqueta: 'Disponibles', valor: '${r.variantesDisponibles}'),
            _TarjetaKpi(etiqueta: 'Reservadas', valor: '${r.variantesReservadas}'),
            _TarjetaKpi(etiqueta: 'Por ingresar', valor: '${r.variantesProximasAIngresar}'),
            _TarjetaKpi(etiqueta: 'Agotadas', valor: '${r.variantesAgotadas}'),
          ],
        ),
      );

  Widget _tarjetaItem(dynamic item) {
    final Widget hijo = switch (item) {
      StockSucursalOut d => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.sucursal, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            FilaDato('Fisico', '${d.totalFisico}'),
            FilaDato('Reservado', '${d.totalReservado}'),
            FilaDato('Disponible', '${d.totalDisponible}'),
            FilaDato('Agotadas', '${d.variantesAgotadas}'),
            FilaDato('Stock bajo', '${d.variantesStockBajo}'),
          ],
        ),
      ReservaEstadoOut d => Row(
          children: [
            Expanded(child: BadgeEstado(d.estado)),
            Text('${d.cantidad}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
      EnvioEstadoOut d => Row(
          children: [
            Expanded(child: BadgeEstado(d.estado)),
            Text('${d.cantidad}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
      ProductoSinMovimientoOut d => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.producto, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${d.talla} · ${d.color}', style: const TextStyle(fontSize: 12, color: Paleta.inkSuave)),
            const SizedBox(height: 6),
            FilaDato('Sucursal', d.sucursal),
            FilaDato('Stock fisico', '${d.cantidadFisica}'),
          ],
        ),
      ClienteRankingOut d => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.cliente, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(d.email, style: const TextStyle(fontSize: 12, color: Paleta.inkSuave)),
            const SizedBox(height: 6),
            FilaDato('Compras', '${d.cantidadCompras}'),
            FilaDato('Monto total', formatearPrecio(d.montoTotal)),
          ],
        ),
      CajaOcupacionOut d => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.sucursal, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            FilaDato('Cajas totales', '${d.totalCajas}'),
            FilaDato('Cajas abiertas', '${d.cajasAbiertas}'),
          ],
        ),
      RecepcionPendienteProveedorOut d => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.proveedor, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            FilaDato('Recepciones', '${d.cantidad}'),
            FilaDato('Monto total', formatearPrecio(d.montoTotal)),
          ],
        ),
      ExistenciaOut d => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(d.producto, style: const TextStyle(fontWeight: FontWeight.w800))),
                BadgeEstado(d.situacion),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${d.sku} · ${d.talla} · ${d.color} · ${d.categoria}',
              style: const TextStyle(fontSize: 11.5, color: Paleta.inkSuave),
            ),
            const SizedBox(height: 6),
            FilaDato('Sucursal', d.sucursal),
            FilaDato('Fisico / reservado / disponible', '${d.cantidadFisica} / ${d.cantidadReservada} / ${d.disponible}'),
            FilaDato('Vendidas / por ingresar', '${d.vendidas} / ${d.proximasAIngresar}'),
          ],
        ),
      _ => const Text('Sin dato'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TarjetaPanel(hijo: hijo),
    );
  }
}

// ---------------------------------------------------------------------------------------
//  Pestana 3: Dinamicos (fecha/sucursal/categoria/canal/entrega), un tipo a la vez
// ---------------------------------------------------------------------------------------

enum _TipoDinamico { ventasDiarias, ventasPorSucursal, topProductos }

extension on _TipoDinamico {
  String get etiqueta => switch (this) {
        _TipoDinamico.ventasDiarias => 'Ventas diarias',
        _TipoDinamico.ventasPorSucursal => 'Ventas por sucursal',
        _TipoDinamico.topProductos => 'Top productos',
      };
}

const _canales = ['WEB', 'MOVIL', 'POS'];
const _entregas = ['RETIRO_SUCURSAL', 'DOMICILIO'];

class _PestanaDinamicos extends StatefulWidget {
  const _PestanaDinamicos({
    required this.sucursales,
    required this.categorias,
    required this.puedeElegirSucursal,
  });

  final List<SucursalOut> sucursales;
  final List<CategoriaOut> categorias;
  final bool puedeElegirSucursal;

  @override
  State<_PestanaDinamicos> createState() => _PestanaDinamicosState();
}

class _PestanaDinamicosState extends State<_PestanaDinamicos> {
  _TipoDinamico _tipo = _TipoDinamico.ventasDiarias;
  DateTime? _desde;
  DateTime? _hasta;
  String? _sucursalId;
  String? _categoriaId;
  String? _canal;
  String? _entrega;

  bool _cargando = true;
  String? _error;
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _consultar();
  }

  Future<void> _consultar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      List<dynamic> items;
      switch (_tipo) {
        case _TipoDinamico.ventasDiarias:
          items = await reportesService.listarVentasDiarias(
            desde: _desde,
            hasta: _hasta,
            sucursalId: _sucursalId,
            categoriaId: _categoriaId,
            canal: _canal,
            entrega: _entrega,
          );
        case _TipoDinamico.ventasPorSucursal:
          items = await reportesService.listarVentasPorSucursal(
            desde: _desde,
            hasta: _hasta,
            sucursalId: _sucursalId,
            categoriaId: _categoriaId,
            canal: _canal,
            entrega: _entrega,
          );
        case _TipoDinamico.topProductos:
          items = await reportesService.listarTopProductos(
            desde: _desde,
            hasta: _hasta,
            sucursalId: _sucursalId,
            categoriaId: _categoriaId,
            canal: _canal,
            entrega: _entrega,
            limite: 15,
          );
      }
      if (!mounted) return;
      setState(() {
        _items = items;
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

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
        children: [
          DropdownButtonFormField<_TipoDinamico>(
            initialValue: _tipo,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tipo de consulta'),
            items: _TipoDinamico.values
                .map((t) => DropdownMenuItem(value: t, child: Text(t.etiqueta)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _tipo = v);
              _consultar();
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SelectorFecha(
                  etiqueta: 'Desde',
                  valor: _desde,
                  alCambiar: (v) => setState(() => _desde = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SelectorFecha(
                  etiqueta: 'Hasta',
                  valor: _hasta,
                  alCambiar: (v) => setState(() => _hasta = v),
                ),
              ),
            ],
          ),
          if (widget.puedeElegirSucursal) ...[
            const SizedBox(height: 10),
            _SelectorSucursal(
              sucursales: widget.sucursales,
              valor: _sucursalId,
              alCambiar: (v) => setState(() => _sucursalId = v),
            ),
          ],
          const SizedBox(height: 10),
          _SelectorCategoria(
            categorias: widget.categorias,
            valor: _categoriaId,
            alCambiar: (v) => setState(() => _categoriaId = v),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _canal,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Canal'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                    ..._canales.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
                  ],
                  onChanged: (v) => setState(() => _canal = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _entrega,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Entrega'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                    ..._entregas.map((e) => DropdownMenuItem<String?>(value: e, child: Text(e))),
                  ],
                  onChanged: (v) => setState(() => _entrega = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _cargando ? null : _consultar, child: const Text('CONSULTAR')),
          const SizedBox(height: 18),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            MensajeError(_error!, alReintentar: _consultar)
          else if (_items.isEmpty)
            const EstadoVacio(mensaje: 'Sin resultados para ese filtro.')
          else
            ..._items.asMap().entries.map((e) => _tarjetaItem(e.key, e.value)),
        ],
      );

  Widget _tarjetaItem(int indice, dynamic item) {
    final Widget hijo = switch (item) {
      VentaDiariaOut d => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(d.dia, style: fuenteMono(fontSize: 13, color: Paleta.ink))),
                BadgeEstado(d.canal, color: Paleta.gold),
              ],
            ),
            const SizedBox(height: 6),
            FilaDato('Sucursal', d.sucursal),
            FilaDato('Ventas', '${d.cantidadVentas}'),
            FilaDato('Monto total', formatearPrecio(d.montoTotal)),
            FilaDato('Ticket promedio', formatearPrecio(d.ticketPromedio)),
          ],
        ),
      VentaPorSucursalOut d => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.sucursal, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            FilaDato('Ventas', '${d.cantidadVentas}'),
            FilaDato('Monto total', formatearPrecio(d.montoTotal)),
            FilaDato('Ticket promedio', formatearPrecio(d.ticketPromedio)),
            FilaDato('Costo de envio', formatearPrecio(d.costoEnvioTotal)),
          ],
        ),
      ProductoRankingOut d => Row(
          children: [
            SizedBox(
              width: 28,
              child: Text('#${indice + 1}', style: fuenteMono(fontSize: 13, color: Paleta.flameOscuro)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.producto, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    '${d.unidadesVendidas} unidad(es) · ${formatearPrecio(d.montoVendido)}',
                    style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave),
                  ),
                ],
              ),
            ),
          ],
        ),
      _ => const Text('Sin dato'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TarjetaPanel(hijo: hijo),
    );
  }
}

// ---------------------------------------------------------------------------------------
//  Pestana 4: Reporte con IA -- mismo patron de tool-use que el asistente de CU18, sobre
//  los reportes de arriba. Dictado por voz con `speech_to_text`, espejo de
//  `asistente_pagina.dart` (unico otro lugar del movil con voz).
// ---------------------------------------------------------------------------------------

class _MensajeVistaIa {
  _MensajeVistaIa({required this.mensaje, this.titulo, this.columnas, this.tabla});

  final MensajeReporte mensaje;
  final String? titulo;
  final List<ColumnaOut>? columnas;
  final List<Map<String, dynamic>>? tabla;
}

class _PestanaIa extends StatefulWidget {
  const _PestanaIa();

  @override
  State<_PestanaIa> createState() => _PestanaIaState();
}

class _PestanaIaState extends State<_PestanaIa> {
  final _mensajes = <_MensajeVistaIa>[];
  final _borrador = TextEditingController();
  final _scroll = ScrollController();
  final _voz = stt.SpeechToText();

  bool _enviando = false;
  String? _error;
  bool _vozDisponible = false;
  bool _escuchando = false;

  @override
  void initState() {
    super.initState();
    _inicializarVoz();
  }

  Future<void> _inicializarVoz() async {
    final disponible = await _voz.initialize(
      onStatus: (estado) {
        if ((estado == 'done' || estado == 'notListening') && mounted) {
          setState(() => _escuchando = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _escuchando = false);
      },
    );
    if (mounted) setState(() => _vozDisponible = disponible);
  }

  Future<void> _alternarEscucha() async {
    if (_escuchando) {
      await _voz.stop();
      if (mounted) setState(() => _escuchando = false);
      return;
    }
    setState(() => _escuchando = true);
    await _voz.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: 'es_BO',
        partialResults: false,
        cancelOnError: true,
      ),
      onResult: (resultado) {
        if (!resultado.finalResult) return;
        final texto = resultado.recognizedWords.trim();
        if (texto.isNotEmpty) {
          _borrador.text = texto;
          _enviar();
        }
        if (mounted) setState(() => _escuchando = false);
      },
    );
  }

  @override
  void dispose() {
    _voz.cancel();
    _borrador.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _borrador.text.trim();
    if (texto.isEmpty || _enviando) return;

    _borrador.clear();
    setState(() {
      _error = null;
      _mensajes.add(_MensajeVistaIa(mensaje: MensajeReporte(rol: 'user', texto: texto)));
      _enviando = true;
    });
    _irAlFinal();

    try {
      final historial = _mensajes.map((v) => v.mensaje).toList();
      final respuesta = await reportesService.consultarIa(historial);
      if (!mounted) return;
      setState(() {
        _mensajes.add(
          _MensajeVistaIa(
            mensaje: MensajeReporte(rol: 'assistant', texto: respuesta.respuesta),
            titulo: respuesta.titulo,
            columnas: respuesta.columnas,
            tabla: respuesta.tabla,
          ),
        );
        _enviando = false;
      });
      _irAlFinal();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = interpretarError(error);
        _enviando = false;
      });
    }
  }

  void _irAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              itemCount: _mensajes.length + 1 + (_enviando ? 1 : 0),
              itemBuilder: (contexto, indice) {
                if (indice == 0) {
                  return const _BurbujaIa(
                    deAsistente: true,
                    child: Text(
                      'Preguntame por ventas, stock, reservas, envios, cajas o recepciones -- '
                      'por ejemplo "como van las ventas de este mes en Santa Cruz".',
                    ),
                  );
                }
                final indiceMensaje = indice - 1;
                if (indiceMensaje >= _mensajes.length) {
                  return const _BurbujaIa(
                    deAsistente: true,
                    cargando: true,
                    child: Text('Consultando…', style: TextStyle(fontStyle: FontStyle.italic)),
                  );
                }
                final vista = _mensajes[indiceMensaje];
                final esUsuario = vista.mensaje.rol == 'user';
                return _BurbujaIa(
                  deAsistente: !esUsuario,
                  titulo: vista.titulo,
                  columnas: vista.columnas,
                  tabla: vista.tabla,
                  child: Text(vista.mensaje.texto),
                );
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: MensajeError(_error!),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _borrador,
                    enabled: !_enviando,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _enviar(),
                    decoration: InputDecoration(
                      hintText: _escuchando ? 'Escuchando…' : 'Ej: ventas de la semana en La Paz',
                    ),
                  ),
                ),
                if (_vozDisponible) ...[
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _enviando ? null : _alternarEscucha,
                    tooltip: _escuchando ? 'Detener dictado' : 'Dictar por voz',
                    style: IconButton.styleFrom(
                      backgroundColor: _escuchando ? Paleta.rojo : Paleta.paperLinea,
                      foregroundColor: _escuchando ? Paleta.blanco : Paleta.ink,
                    ),
                    icon: Icon(_escuchando ? Icons.mic : Icons.mic_none),
                  ),
                ],
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: _enviando ? null : _enviar,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      );
}

class _BurbujaIa extends StatelessWidget {
  const _BurbujaIa({
    required this.deAsistente,
    required this.child,
    this.titulo,
    this.columnas,
    this.tabla,
    this.cargando = false,
  });

  final bool deAsistente;
  final Widget child;
  final String? titulo;
  final List<ColumnaOut>? columnas;
  final List<Map<String, dynamic>>? tabla;
  final bool cargando;

  @override
  Widget build(BuildContext context) => Align(
        alignment: deAsistente ? Alignment.centerLeft : Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: deAsistente ? Paleta.blanco : Paleta.ink,
            border: deAsistente ? Border.all(color: Paleta.paperLinea) : null,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(deAsistente ? 4 : 14),
              bottomRight: Radius.circular(deAsistente ? 14 : 4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DefaultTextStyle.merge(
                style: TextStyle(
                  color: deAsistente ? (cargando ? Paleta.inkSuave : Paleta.ink) : Paleta.paper,
                  height: 1.4,
                ),
                child: child,
              ),
              if (tabla != null && tabla!.isNotEmpty && columnas != null && columnas!.isNotEmpty) ...[
                const SizedBox(height: 10),
                if (titulo != null) ...[
                  EtiquetaDato(titulo!),
                  const SizedBox(height: 6),
                ],
                _TablaResultadoIa(columnas: columnas!, filas: tabla!),
              ],
            ],
          ),
        ),
      );
}

/// Tabla generica de la respuesta de IA: una columna por cada `ColumnaOut`, con scroll
/// horizontal si no entra en el ancho. No hay grafico ni exportacion aca (fuera de
/// alcance, ver PENDIENTES.txt); esto solo muestra el detalle crudo que ya trajo la
/// herramienta que Claude llamo.
class _TablaResultadoIa extends StatelessWidget {
  const _TablaResultadoIa({required this.columnas, required this.filas});

  final List<ColumnaOut> columnas;
  final List<Map<String, dynamic>> filas;

  String _formatear(dynamic valor) {
    if (valor == null) return '-';
    if (valor is double) return valor.toStringAsFixed(2);
    return valor.toString();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 18,
          headingRowHeight: 34,
          dataRowMinHeight: 32,
          dataRowMaxHeight: 40,
          headingTextStyle: fuenteMono(fontSize: 10.5, color: Paleta.inkSuave),
          dataTextStyle: const TextStyle(fontSize: 12.5, color: Paleta.ink),
          columns: columnas.map((c) => DataColumn(label: Text(c.etiqueta))).toList(),
          rows: filas
              .map(
                (fila) => DataRow(
                  cells: columnas.map((c) => DataCell(Text(_formatear(fila[c.clave])))).toList(),
                ),
              )
              .toList(),
        ),
      );
}

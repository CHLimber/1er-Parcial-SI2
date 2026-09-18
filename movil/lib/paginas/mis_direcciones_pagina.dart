import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../compartido/widgets.dart';
import '../core/direcciones/direcciones_models.dart';
import '../core/direcciones/direcciones_service.dart';
import '../core/errores.dart';
import '../core/tema.dart';

/// CU20 - libreta de direcciones. Es el paso previo al delivery: sin un punto en el mapa el
/// checkout no puede cotizar el envio.
///
/// El mapa es flutter_map sobre tiles de OpenStreetMap (los mismos datos con los que
/// openrouteservice calcula la ruta del lado del backend), el equivalente movil del
/// componente Leaflet de la web.
class MisDireccionesPagina extends StatefulWidget {
  const MisDireccionesPagina({super.key});

  @override
  State<MisDireccionesPagina> createState() => _MisDireccionesPaginaState();
}

class _MisDireccionesPaginaState extends State<MisDireccionesPagina> {
  List<DireccionOut> _direcciones = const [];
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
      final direcciones = await direccionesService.listar();
      if (!mounted) return;
      setState(() {
        _direcciones = direcciones;
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

  Future<void> _abrirFormulario({DireccionOut? direccion}) async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _FormularioDireccion(
          direccion: direccion,
          esPrimera: _direcciones.isEmpty,
        ),
      ),
    );
    if (guardado == true) _cargar();
  }

  Future<void> _marcarPrincipal(DireccionOut direccion) async {
    try {
      await direccionesService.marcarPrincipal(direccion.id);
      if (!mounted) return;
      mostrarAviso(context, '"${direccion.alias}" es ahora tu direccion principal');
      _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  Future<void> _eliminar(DireccionOut direccion) async {
    final confirmado = await confirmar(
      context,
      titulo: 'Borrar direccion',
      mensaje: 'Se quitara "${direccion.alias}" de tu libreta.',
      textoConfirmar: 'Borrar',
      destructivo: true,
    );
    if (!confirmado || !mounted) return;

    try {
      await direccionesService.eliminar(direccion.id);
      if (!mounted) return;
      mostrarAviso(context, 'Direccion borrada');
      _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis direcciones')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('AGREGAR'),
      ),
      body: VistaAsincrona(
        cargando: _cargando,
        error: _error,
        alReintentar: _cargar,
        hijo: _direcciones.isEmpty
            ? const EstadoVacio(
                icono: Icons.location_off_outlined,
                mensaje:
                    'Todavia no tenes direcciones guardadas.\nAgrega una y te llevamos el pedido a casa.',
              )
            : RefreshIndicator(
                onRefresh: _cargar,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: _direcciones.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (contexto, indice) {
                    final direccion = _direcciones[indice];
                    return TarjetaPanel(
                      hijo: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  direccion.alias,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              if (direccion.esPrincipal)
                                const BadgeEstado('PRINCIPAL', color: Paleta.flame),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(direccion.direccion),
                          Text(
                            ciudadesBolivia[direccion.ciudad] ?? direccion.ciudad,
                            style: const TextStyle(color: Paleta.inkSuave, fontSize: 13),
                          ),
                          if (direccion.referencia != null)
                            Text(
                              direccion.referencia!,
                              style: const TextStyle(color: Paleta.inkSuave, fontSize: 13),
                            ),
                          if (!direccion.tienePunto)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                'Sin punto en el mapa: no se puede calcular el envio.',
                                style: TextStyle(color: Paleta.rojo, fontSize: 12.5),
                              ),
                            ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => _abrirFormulario(direccion: direccion),
                                child: const Text('Editar'),
                              ),
                              if (!direccion.esPrincipal)
                                TextButton(
                                  onPressed: () => _marcarPrincipal(direccion),
                                  child: const Text('Hacer principal'),
                                ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Borrar',
                                onPressed: () => _eliminar(direccion),
                                icon: const Icon(Icons.delete_outline, color: Paleta.rojo),
                              ),
                            ],
                          ),
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

class _FormularioDireccion extends StatefulWidget {
  const _FormularioDireccion({this.direccion, this.esPrimera = false});

  final DireccionOut? direccion;
  final bool esPrimera;

  @override
  State<_FormularioDireccion> createState() => _FormularioDireccionState();
}

class _FormularioDireccionState extends State<_FormularioDireccion> {
  final _alias = TextEditingController();
  final _calle = TextEditingController();
  final _referencia = TextEditingController();
  final _busqueda = TextEditingController();
  final _mapa = MapController();

  String _ciudad = 'SANTA_CRUZ';
  bool _esPrincipal = false;
  bool _guardando = false;
  bool _buscando = false;
  bool _geocodificadorDisponible = true;
  List<SugerenciaDireccion> _sugerencias = const [];
  LatLng? _punto;

  // Santa Cruz de la Sierra: vista inicial cuando todavia no hay punto elegido.
  static const _centroPorDefecto = LatLng(-17.7833, -63.1821);

  @override
  void initState() {
    super.initState();
    final direccion = widget.direccion;
    if (direccion != null) {
      _alias.text = direccion.alias;
      _calle.text = direccion.direccion;
      _referencia.text = direccion.referencia ?? '';
      _ciudad = direccion.ciudad;
      _esPrincipal = direccion.esPrincipal;
      if (direccion.tienePunto) {
        _punto = LatLng(direccion.latitud!, direccion.longitud!);
      }
    } else {
      _esPrincipal = widget.esPrimera;
    }
  }

  @override
  void dispose() {
    _alias.dispose();
    _calle.dispose();
    _referencia.dispose();
    _busqueda.dispose();
    _mapa.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final texto = _busqueda.text.trim();
    if (texto.length < 3) return;

    setState(() => _buscando = true);
    try {
      final resultado = await direccionesService.buscar(texto);
      if (!mounted) return;
      setState(() {
        _geocodificadorDisponible = resultado.geocodificadorDisponible;
        _sugerencias = resultado.resultados;
        _buscando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sugerencias = const [];
        _buscando = false;
      });
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  void _usarSugerencia(SugerenciaDireccion sugerencia) {
    final punto = LatLng(sugerencia.latitud, sugerencia.longitud);
    setState(() {
      _punto = punto;
      _sugerencias = const [];
      if (_calle.text.trim().isEmpty) _calle.text = sugerencia.etiqueta;
    });
    _mapa.move(punto, 16);
  }

  Future<void> _guardar() async {
    if (_alias.text.trim().length < 2 || _calle.text.trim().length < 5) {
      mostrarAviso(context, 'Completa el nombre de la direccion y la calle', esError: true);
      return;
    }
    if (_punto == null) {
      mostrarAviso(
        context,
        'Marca en el mapa donde queda: sin ese punto no podemos calcular el envio',
        esError: true,
      );
      return;
    }

    final datos = DireccionIn(
      alias: _alias.text.trim(),
      ciudad: _ciudad,
      direccion: _calle.text.trim(),
      referencia: _referencia.text.trim(),
      latitud: _punto!.latitude,
      longitud: _punto!.longitude,
      esPrincipal: _esPrincipal,
    );

    setState(() => _guardando = true);
    try {
      if (widget.direccion == null) {
        await direccionesService.crear(datos);
      } else {
        await direccionesService.actualizar(widget.direccion!.id, datos);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _guardando = false);
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.direccion == null ? 'Nueva direccion' : 'Editar direccion'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          TextField(
            controller: _alias,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              hintText: 'Casa, Oficina...',
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _ciudad,
            decoration: const InputDecoration(labelText: 'Ciudad'),
            items: ciudadesBolivia.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (valor) => setState(() => _ciudad = valor ?? _ciudad),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _calle,
            decoration: const InputDecoration(
              labelText: 'Calle y numero',
              hintText: 'Av. Cristobal de Mendoza #1200',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _referencia,
            decoration: const InputDecoration(
              labelText: 'Referencia (opcional)',
              hintText: 'Porton verde, frente a la plaza',
            ),
          ),
          const SizedBox(height: 20),
          const EtiquetaDato('Donde queda'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _busqueda,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _buscar(),
                  decoration: const InputDecoration(
                    labelText: 'Buscar direccion',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _buscando ? null : _buscar,
                child: Text(_buscando ? '...' : 'IR'),
              ),
            ],
          ),
          if (_sugerencias.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: _sugerencias
                    .map(
                      (sugerencia) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.place_outlined, size: 20),
                        title: Text(sugerencia.etiqueta, style: const TextStyle(fontSize: 13.5)),
                        onTap: () => _usarSugerencia(sugerencia),
                      ),
                    )
                    .toList(),
              ),
            )
          else if (!_geocodificadorDisponible)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'El buscador de direcciones no esta configurado en el servidor. '
                'Toca el mapa para marcar donde queda.',
                style: TextStyle(color: Paleta.inkSuave, fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 260,
              child: FlutterMap(
                mapController: _mapa,
                options: MapOptions(
                  initialCenter: _punto ?? _centroPorDefecto,
                  initialZoom: _punto == null ? 12 : 16,
                  onTap: (_, punto) => setState(() => _punto = punto),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'bo.fashionstore.movil',
                  ),
                  if (_punto != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _punto!,
                          width: 40,
                          height: 40,
                          alignment: Alignment.topCenter,
                          child: const Icon(Icons.place, color: Paleta.flame, size: 38),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _punto == null
                ? 'Toca el mapa para marcar la puerta de tu casa.'
                : 'Punto elegido: ${_punto!.latitude.toStringAsFixed(5)}, '
                    '${_punto!.longitude.toStringAsFixed(5)}',
            style: const TextStyle(color: Paleta.inkSuave, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _esPrincipal,
            onChanged: (valor) => setState(() => _esPrincipal = valor),
            title: const Text('Usar como direccion principal'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: Text(_guardando ? 'GUARDANDO...' : 'GUARDAR DIRECCION'),
          ),
        ],
      ),
    );
  }
}

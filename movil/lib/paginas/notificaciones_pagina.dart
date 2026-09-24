import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/errores.dart';
import '../core/notificaciones/notificaciones_models.dart';
import '../core/notificaciones/notificaciones_service.dart';
import '../core/tema.dart';

/// Campana con el contador de no leidas para la AppBar (tienda y cuenta). Abre
/// [NotificacionesPagina]; el numero lo mantiene [NotificacionesService] por polling.
class BotonNotificaciones extends StatelessWidget {
  const BotonNotificaciones({super.key});

  @override
  Widget build(BuildContext context) {
    final noLeidas = context.watch<NotificacionesService>().noLeidas;
    return IconButton(
      tooltip: noLeidas > 0 ? 'Notificaciones ($noLeidas sin leer)' : 'Notificaciones',
      onPressed: () => context.push('/notificaciones'),
      icon: Badge(
        isLabelVisible: noLeidas > 0,
        backgroundColor: Paleta.flame,
        label: Text(noLeidas > 99 ? '99+' : '$noLeidas'),
        child: Icon(noLeidas > 0 ? Icons.notifications : Icons.notifications_none),
      ),
    );
  }
}

/// Lista de notificaciones del usuario de la sesion (PENDIENTES.txt 2.19.3), cliente o
/// personal. Tocar un aviso lo marca como leido y, si hay una pantalla que lo explique en la
/// app, navega a ella (ver [_destino]).
class NotificacionesPagina extends StatefulWidget {
  const NotificacionesPagina({super.key});

  @override
  State<NotificacionesPagina> createState() => _NotificacionesPaginaState();
}

class _NotificacionesPaginaState extends State<NotificacionesPagina> {
  static const int _porPagina = 20;

  final _scroll = ScrollController();

  List<NotificacionOut> _items = [];
  int _total = 0;
  int _pagina = 1;
  bool _cargando = true;
  bool _cargandoMas = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_alDesplazar);
    _cargar();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _alDesplazar() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _cargarMas();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final respuesta = await context.read<NotificacionesService>().listar(tamanioPagina: _porPagina);
      if (!mounted) return;
      setState(() {
        _items = respuesta.items;
        _total = respuesta.total;
        _pagina = 1;
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

  Future<void> _cargarMas() async {
    if (_cargando || _cargandoMas || _items.length >= _total) return;
    setState(() => _cargandoMas = true);
    try {
      final respuesta = await context
          .read<NotificacionesService>()
          .listar(pagina: _pagina + 1, tamanioPagina: _porPagina);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...respuesta.items];
        _total = respuesta.total;
        _pagina = respuesta.pagina;
      });
    } catch (error) {
      if (mounted) mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _cargandoMas = false);
    }
  }

  Future<void> _leerTodas() async {
    try {
      await context.read<NotificacionesService>().leerTodas();
      if (!mounted) return;
      setState(() => _items = _items.map((n) => n.leida ? n : n.copiarLeida()).toList());
    } catch (error) {
      if (mounted) mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  void _abrir(NotificacionOut notificacion) {
    if (!notificacion.leida) {
      setState(() {
        _items = _items.map((n) => n.id == notificacion.id ? n.copiarLeida() : n).toList();
      });
      // si falla, el proximo refresco del contador lo corrige
      context.read<NotificacionesService>().marcarLeida(notificacion.id).catchError(
            (_) => notificacion,
          );
    }

    final destino = _destino(notificacion);
    if (destino == null) return;
    // las pestanias de la barra inferior se abren con go; el resto se apila con push
    if (destino == '/tienda' || destino == '/mis-reservas') {
      context.go(destino);
    } else {
      context.push(destino);
    }
  }

  /// Espejo de `destino` en la campana web, recortado a las pantallas que existen en la app
  /// (el movil no tiene inventario del panel, asi que STOCK solo se marca leido).
  String? _destino(NotificacionOut n) {
    final auth = context.read<AuthService>();
    if (n.tipo == 'STOCK') return null;
    if (n.tipo == 'PROMO') return '/tienda';

    if (n.entidadTipo == 'RESERVA' || n.tipo == 'RESERVA') {
      if (!auth.esStaff) return '/mis-reservas';
      return auth.tienePermiso([permisoAtenderReservas]) ? '/atender-reservas' : null;
    }

    if (!auth.esStaff) return n.ventaId != null ? '/compra/${n.ventaId}' : '/mis-compras';
    if (n.entidadTipo == 'VENTA' && auth.tienePermiso([permisoCaja])) return '/caja';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final noLeidas = context.watch<NotificacionesService>().noLeidas;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          if (noLeidas > 0 && !_cargando)
            IconButton(
              tooltip: 'Marcar todas como leidas',
              onPressed: _leerTodas,
              icon: const Icon(Icons.done_all),
            ),
        ],
      ),
      body: VistaAsincrona(
        cargando: _cargando,
        error: _error,
        alReintentar: _cargar,
        hijo: RefreshIndicator(
          color: Paleta.flame,
          onRefresh: _cargar,
          child: _items.isEmpty
              ? ListView(
                  // ListView para que el pull-to-refresh funcione tambien sin avisos
                  children: const [
                    SizedBox(height: 80),
                    EstadoVacio(
                      mensaje: 'No tienes notificaciones por ahora.',
                      icono: Icons.notifications_none,
                    ),
                  ],
                )
              : ListView.separated(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  itemCount: _items.length + (_cargandoMas ? 1 : 0),
                  separatorBuilder: (contexto, indice) => const SizedBox(height: 10),
                  itemBuilder: (contexto, indice) {
                    if (indice >= _items.length) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final n = _items[indice];
                    return _TarjetaNotificacion(
                      notificacion: n,
                      conDestino: _destino(n) != null,
                      alTocar: () => _abrir(n),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _TarjetaNotificacion extends StatelessWidget {
  const _TarjetaNotificacion({
    required this.notificacion,
    required this.conDestino,
    required this.alTocar,
  });

  final NotificacionOut notificacion;
  final bool conDestino;
  final VoidCallback alTocar;

  static String _etiqueta(NotificacionOut n) {
    if (n.entidadTipo == 'ENVIO') return 'ENVIO';
    switch (n.tipo) {
      case 'RESERVA':
        return 'RESERVA';
      case 'VENTA':
        return 'COMPRA';
      case 'STOCK':
        return 'STOCK';
      case 'PROMO':
        return 'PROMOCION';
      default:
        return n.tipo;
    }
  }

  static IconData _icono(NotificacionOut n) {
    if (n.entidadTipo == 'ENVIO') return Icons.local_shipping_outlined;
    switch (n.tipo) {
      case 'RESERVA':
        return Icons.checkroom_outlined;
      case 'VENTA':
        return Icons.receipt_long_outlined;
      case 'STOCK':
        return Icons.inventory_2_outlined;
      default:
        return Icons.local_offer_outlined;
    }
  }

  static String _fecha(DateTime fecha) {
    final f = fecha.toLocal();
    String dos(int v) => v.toString().padLeft(2, '0');
    return '${dos(f.day)}/${dos(f.month)} ${dos(f.hour)}:${dos(f.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final n = notificacion;
    final nueva = !n.leida;
    return TarjetaPanel(
      alTocar: alTocar,
      hijo: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: nueva ? Paleta.flame.withValues(alpha: 0.12) : Paleta.paper,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icono(n), size: 20, color: nueva ? Paleta.flame : Paleta.inkSuave),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _etiqueta(n),
                      style: fuenteMono(fontSize: 11, fontWeight: FontWeight.w700, color: Paleta.gold),
                    ),
                    const Spacer(),
                    if (n.fecha != null)
                      Text(
                        _fecha(n.fecha!),
                        style: fuenteMono(fontSize: 11, color: Paleta.inkSuave),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (nueva) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: Paleta.flame, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        n.titulo,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: nueva ? FontWeight.w800 : FontWeight.w600,
                          color: Paleta.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  n.mensaje,
                  style: const TextStyle(fontSize: 13, color: Paleta.inkSuave, height: 1.35),
                ),
              ],
            ),
          ),
          if (conDestino) ...[
            const SizedBox(width: 6),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Icon(Icons.chevron_right, color: Paleta.inkSuave),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/carrito/carrito_service.dart';
import '../core/errores.dart';
import '../core/reservas/reserva_carrito_service.dart';
import '../core/reservas/reservas_models.dart';
import '../core/reservas/reservas_service.dart';
import '../core/tema.dart';

/// CU04 (seguimiento de reservas) y puerta de entrada a CU05 desde una reserva.
class MisReservasPagina extends StatefulWidget {
  const MisReservasPagina({super.key});

  @override
  State<MisReservasPagina> createState() => _MisReservasPaginaState();
}

class _MisReservasPaginaState extends State<MisReservasPagina> {
  List<ReservaOut> _reservas = [];
  bool _cargando = true;
  String? _error;
  String? _convirtiendo;

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
      final reservas = await reservasService.listarMisReservas();
      if (!mounted) return;
      setState(() {
        _reservas = reservas;
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

  /// CU05 desde reserva: el carrito nace con lo que ya esta comprometido en la sucursal.
  Future<void> _comprarReserva(ReservaOut reserva) async {
    setState(() => _convirtiendo = reserva.id);
    try {
      await context.read<CarritoService>().crearDesdeReserva(reserva.id);
      if (!mounted) return;
      context.go('/carrito');
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _convirtiendo = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bolsa = context.watch<ReservaCarritoService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis reservas'),
        actions: [
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          if (!bolsa.estaVacio)
            Container(
              width: double.infinity,
              color: Paleta.gold.withValues(alpha: 0.14),
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.shopping_basket_outlined, color: Paleta.gold),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tienes ${bolsa.cantidadTotal} prenda(s) en tu bolsa sin reservar.',
                      style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/reservar'),
                    child: const Text('Continuar'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: VistaAsincrona(
              cargando: _cargando,
              error: _error,
              alReintentar: _cargar,
              hijo: _reservas.isEmpty
                  ? EstadoVacio(
                      mensaje: 'Todavia no reservaste ninguna prenda.',
                      icono: Icons.event_available_outlined,
                      accion: ElevatedButton(
                        onPressed: () => context.go('/tienda'),
                        child: const Text('VER CATALOGO'),
                      ),
                    )
                  : RefreshIndicator(
                      color: Paleta.flame,
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        itemCount: _reservas.length,
                        separatorBuilder: (contexto, indice) => const SizedBox(height: 12),
                        itemBuilder: (contexto, indice) => _tarjeta(_reservas[indice]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(ReservaOut reserva) {
    final convirtiendo = _convirtiendo == reserva.id;

    return TarjetaPanel(
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reserva.codigo,
                  style: fuenteMono(fontSize: 15, fontWeight: FontWeight.w700, color: Paleta.ink),
                ),
              ),
              BadgeEstado(reserva.estado),
            ],
          ),
          const SizedBox(height: 10),
          FilaDato('Sucursal', reserva.sucursal),
          FilaDato('Visita', '${reserva.fechaVisita} a las ${reserva.horaVisita.substring(0, 5)}'),
          if (reserva.expiraEn != null)
            FilaDato('Vence', _fechaLegible(reserva.expiraEn!)),
          if (reserva.observaciones != null && reserva.observaciones!.isNotEmpty)
            FilaDato('Nota', reserva.observaciones!),
          const SizedBox(height: 10),
          const EtiquetaDato('Prendas apartadas'),
          const SizedBox(height: 6),
          ...reserva.items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.cantidad} x ${item.producto} · ${item.talla} · ${item.color}',
                      style: const TextStyle(fontSize: 13.5, height: 1.3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  BadgeEstado(item.estadoItem),
                ],
              ),
            ),
          ),
          if (reserva.estaVigente) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: convirtiendo ? null : () => _comprarReserva(reserva),
                icon: convirtiendo
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.shopping_bag_outlined),
                label: const Text('COMPRAR ESTA RESERVA'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _fechaLegible(DateTime fecha) {
  final local = fecha.toLocal();
  String dosDigitos(int valor) => valor.toString().padLeft(2, '0');
  return '${dosDigitos(local.day)}/${dosDigitos(local.month)}/${local.year} '
      '${dosDigitos(local.hour)}:${dosDigitos(local.minute)}';
}

String fechaLegible(DateTime fecha) => _fechaLegible(fecha);

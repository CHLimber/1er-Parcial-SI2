import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../compartido/widgets.dart';
import '../core/config.dart';
import '../core/errores.dart';
import '../core/tema.dart';
import '../core/ventas/ventas_models.dart';
import '../core/ventas/ventas_service.dart';
import 'mis_reservas_pagina.dart' show fechaLegible;

/// Historial de compras del cliente (cierre de CU05/CU06).
class MisComprasPagina extends StatefulWidget {
  const MisComprasPagina({super.key});

  @override
  State<MisComprasPagina> createState() => _MisComprasPaginaState();
}

class _MisComprasPaginaState extends State<MisComprasPagina> {
  List<VentaResumenOut> _compras = [];
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
      final compras = await ventasService.listarMisCompras();
      if (!mounted) return;
      setState(() {
        _compras = compras;
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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mis compras')),
        body: VistaAsincrona(
          cargando: _cargando,
          error: _error,
          alReintentar: _cargar,
          hijo: _compras.isEmpty
              ? const EstadoVacio(
                  mensaje: 'Todavia no tienes compras registradas.',
                  icono: Icons.receipt_long_outlined,
                )
              : RefreshIndicator(
                  color: Paleta.flame,
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    itemCount: _compras.length,
                    separatorBuilder: (contexto, indice) => const SizedBox(height: 10),
                    itemBuilder: (contexto, indice) {
                      final compra = _compras[indice];
                      return TarjetaPanel(
                        alTocar: () => context.push('/compra/${compra.id}'),
                        hijo: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    compra.numero,
                                    style: fuenteMono(fontSize: 14, fontWeight: FontWeight.w700, color: Paleta.ink),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${compra.sucursal} · ${compra.canal}',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Paleta.inkSuave,
                                    ),
                                  ),
                                  if (compra.fecha != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      fechaLegible(compra.fecha!),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Paleta.inkSuave,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                BadgeEstado(compra.estado),
                                const SizedBox(height: 6),
                                Text(
                                  formatearPrecio(compra.total),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
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

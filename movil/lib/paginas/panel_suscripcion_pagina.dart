import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../compartido/widgets.dart';
import '../core/config.dart';
import '../core/errores.dart';
import '../core/saas/saas_service.dart';
import '../core/tema.dart';
import 'mis_reservas_pagina.dart' show fechaLegible;

/// Suscripcion del tenant (Segundo parcial, PENDIENTES 5.4-5.6), espejo de `panel-suscripcion`
/// de la web: plan, estado, uso contra los topes y los tres planes. Pagar abre el Checkout de
/// Stripe en el navegador; al volver se refresca (el webhook aplica el pago).
class PanelSuscripcionPagina extends StatefulWidget {
  const PanelSuscripcionPagina({super.key});

  @override
  State<PanelSuscripcionPagina> createState() => _PanelSuscripcionPaginaState();
}

class _PanelSuscripcionPaginaState extends State<PanelSuscripcionPagina> with WidgetsBindingObserver {
  List<SuscripcionOut>? _tenants;
  List<PlanOut> _planes = [];
  SuscripcionOut? _actual;
  String? _error;
  int _meses = 1;
  bool _pagando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // al volver del navegador (Checkout de Stripe) se recarga el estado
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed && _pagando) {
      _pagando = false;
      _cargar();
    }
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final resultados = await Future.wait([saasService.suscripciones(), saasService.planes()]);
      if (!mounted) return;
      final tenants = resultados[0] as List<SuscripcionOut>;
      setState(() {
        _tenants = tenants;
        _planes = resultados[1] as List<PlanOut>;
        _actual = tenants.where((t) => t.sucursalId == _actual?.sucursalId).firstOrNull ??
            (tenants.isEmpty ? null : tenants.first);
      });
    } catch (error) {
      if (mounted) setState(() => _error = interpretarError(error));
    }
  }

  Future<void> _pagar(PlanOut plan) async {
    final actual = _actual;
    if (actual == null) return;
    try {
      final url = await saasService.iniciarPago(plan.codigo, _meses, actual.sucursalId);
      _pagando = true;
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (error) {
      if (mounted) mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  String _tope(int? valor) => valor == null ? 'sin limite' : '$valor';

  @override
  Widget build(BuildContext context) {
    final tenants = _tenants;
    final actual = _actual;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suscripcion'),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          if (_error != null) MensajeError(_error!, alReintentar: _cargar),
          if (tenants == null && _error == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (tenants != null && tenants.length > 1)
            DropdownButtonFormField<String>(
              initialValue: actual?.sucursalId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tenant (sucursal)'),
              items: tenants
                  .map((t) => DropdownMenuItem(value: t.sucursalId, child: Text('${t.sucursal} · ${t.plan.nombre}')))
                  .toList(),
              onChanged: (id) => setState(() => _actual = tenants.firstWhere((t) => t.sucursalId == id)),
            ),
          if (actual != null) ...[
            const SizedBox(height: 12),
            TarjetaPanel(
              hijo: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(actual.sucursal, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      BadgeEstado(
                        actual.vigente ? (actual.estado == 'PRUEBA' ? 'EN PRUEBA' : 'AL DIA') : 'VENCIDA',
                        color: actual.vigente ? Paleta.verde : Paleta.rojo,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilaDato('Plan', actual.plan.nombre),
                  FilaDato(actual.vigente ? 'Vence' : 'Vencio', fechaLegible(actual.venceEn.toLocal())),
                  if (actual.vigente) FilaDato('Dias restantes', '${actual.diasRestantes}'),
                  FilaDato('Personal', '${actual.empleados} / ${_tope(actual.plan.maxEmpleados)}'),
                  FilaDato('Cajas', '${actual.cajas} / ${_tope(actual.plan.maxCajas)}'),
                  if (!actual.vigente)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Vencida: perfil de clientas, traspasos y reportes con IA quedan bloqueados.',
                        style: TextStyle(color: Paleta.rojo, fontSize: 12.5),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const EtiquetaDato('Planes'),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _meses,
              decoration: const InputDecoration(labelText: 'Meses a pagar'),
              items: const [1, 3, 6, 12].map((m) => DropdownMenuItem(value: m, child: Text('$m'))).toList(),
              onChanged: (m) => setState(() => _meses = m ?? 1),
            ),
            const SizedBox(height: 10),
            ..._planes.map(
              (plan) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TarjetaPanel(
                  hijo: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(plan.nombre, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          ),
                          Text('${formatearPrecio(plan.precioMensual)} / mes'),
                        ],
                      ),
                      if (plan.descripcion != null)
                        Text(plan.descripcion!, style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave)),
                      const SizedBox(height: 6),
                      Text(
                        'Personal ${_tope(plan.maxEmpleados)} · cajas ${_tope(plan.maxCajas)}\n'
                        '${plan.perfilesClientes ? '✓' : '✗'} perfil de clientas · '
                        '${plan.traspasos ? '✓' : '✗'} traspasos · ${plan.iaReportes ? '✓' : '✗'} reportes con IA',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          onPressed: () => _pagar(plan),
                          child: Text(
                            '${plan.codigo == actual.plan.codigo ? 'RENOVAR' : 'CAMBIAR'} · '
                            '${formatearPrecio(plan.precioMensual * _meses)}',
                          ),
                        ),
                      ),
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
}

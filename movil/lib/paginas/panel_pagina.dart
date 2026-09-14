import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/tema.dart';

/// Hub del panel de gestion (CU09 a CU13). Los accesos se arman con los permisos del
/// rol, igual que `panel-shell` en la web; quien autoriza de verdad es la API.
class PanelPagina extends StatelessWidget {
  const PanelPagina({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final usuario = auth.usuario;

    final accesos = <_AccesoPanel>[
      _AccesoPanel(
        ruta: '/panel/recepciones',
        icono: Icons.local_shipping_outlined,
        titulo: 'Recepciones',
        detalle: 'CU09 · Entrada de mercaderia al inventario',
        permisos: const ['recepciones.ver', 'recepciones.registrar', 'recepciones.confirmar'],
      ),
      _AccesoPanel(
        ruta: '/panel/catalogo',
        icono: Icons.checkroom_outlined,
        titulo: 'Catalogo',
        detalle: 'CU10 · Prendas, variantes y categorias',
        permisos: const ['catalogo.ver', 'catalogo.gestionar'],
      ),
      _AccesoPanel(
        ruta: '/panel/proveedores',
        icono: Icons.handshake_outlined,
        titulo: 'Proveedores',
        detalle: 'CU11 · Quienes nos abastecen',
        permisos: const ['proveedores.ver', 'proveedores.gestionar'],
      ),
      _AccesoPanel(
        ruta: '/panel/sucursales',
        icono: Icons.store_outlined,
        titulo: 'Sucursales',
        detalle: 'CU12 · Tiendas y cajas',
        permisos: const ['sucursales.ver', 'sucursales.gestionar'],
      ),
      _AccesoPanel(
        ruta: '/panel/usuarios',
        icono: Icons.badge_outlined,
        titulo: 'Usuarios y roles',
        detalle: 'CU13 · Personal, roles y permisos',
        permisos: const ['usuarios.ver', 'usuarios.gestionar', 'roles.ver'],
      ),
    ];

    final habilitados = accesos.where((a) => auth.tienePermiso(a.permisos)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Panel de gestion')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          Titular('Hola, ${usuario?.nombre ?? ""}', tamano: 26),
          const SizedBox(height: 6),
          Text(
            usuario?.rol == null
                ? 'Tu usuario no tiene un rol asignado.'
                : 'Rol ${usuario!.rol}. Ves solo lo que tu rol tiene permitido.',
            style: const TextStyle(color: Paleta.inkSuave, height: 1.4),
          ),
          const SizedBox(height: 22),
          if (habilitados.isEmpty)
            const EstadoVacio(
              mensaje: 'Tu rol no tiene permisos sobre ningun modulo de gestion.',
              icono: Icons.lock_outline,
            )
          else
            ...habilitados.map(
              (acceso) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TarjetaPanel(
                  alTocar: () => context.push(acceso.ruta),
                  hijo: Row(
                    children: [
                      Icon(acceso.icono, color: Paleta.flame, size: 26),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              acceso.titulo,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              acceso.detalle,
                              style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Paleta.inkSuave),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccesoPanel {
  const _AccesoPanel({
    required this.ruta,
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.permisos,
  });

  final String ruta;
  final IconData icono;
  final String titulo;
  final String detalle;
  final List<String> permisos;
}

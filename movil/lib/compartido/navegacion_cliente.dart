import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/carrito/carrito_service.dart';
import '../core/reservas/reserva_carrito_service.dart';
import '../core/tema.dart';

/// Barra inferior de las cuatro pantallas de uso diario del cliente. El panel de gestion
/// y las pantallas de sucursal (CU07/CU08) se abren encima, desde Cuenta.
class NavegacionCliente extends StatelessWidget {
  const NavegacionCliente({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final enReserva = context.watch<ReservaCarritoService>().cantidadTotal;
    final enCarrito = context.watch<CarritoService>().cantidadItems;

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (indice) =>
            shell.goBranch(indice, initialLocation: indice == shell.currentIndex),
        backgroundColor: Paleta.blanco,
        indicatorColor: Paleta.flame.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Tienda',
          ),
          NavigationDestination(
            icon: _ConContador(cantidad: enReserva, icono: Icons.checkroom_outlined),
            selectedIcon: _ConContador(cantidad: enReserva, icono: Icons.checkroom),
            label: 'Reservas',
          ),
          NavigationDestination(
            icon: _ConContador(cantidad: enCarrito, icono: Icons.shopping_bag_outlined),
            selectedIcon: _ConContador(cantidad: enCarrito, icono: Icons.shopping_bag),
            label: 'Carrito',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Cuenta',
          ),
        ],
      ),
    );
  }
}

class _ConContador extends StatelessWidget {
  const _ConContador({required this.cantidad, required this.icono});

  final int cantidad;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    if (cantidad <= 0) return Icon(icono);
    return Badge(
      backgroundColor: Paleta.flame,
      label: Text('$cantidad'),
      child: Icon(icono),
    );
  }
}

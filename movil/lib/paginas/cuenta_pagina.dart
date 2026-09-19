import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/carrito/carrito_service.dart';
import '../core/config.dart';
import '../core/errores.dart';
import '../core/tema.dart';

/// Cuenta del usuario: datos de sesion, accesos del cliente y, para el personal, la
/// puerta a caja (CU07), atencion de reservas (CU08) y el panel de gestion (CU09-CU13).
class CuentaPagina extends StatefulWidget {
  const CuentaPagina({super.key});

  @override
  State<CuentaPagina> createState() => _CuentaPaginaState();
}

class _CuentaPaginaState extends State<CuentaPagina> {
  bool _refrescando = false;

  /// Si el administrador cambio el rol o sus permisos (CU13), la sesion guardada en el
  /// telefono queda vieja hasta este refresco.
  Future<void> _refrescarSesion() async {
    setState(() => _refrescando = true);
    try {
      await context.read<AuthService>().refrescarSesion();
      if (!mounted) return;
      mostrarAviso(context, 'Sesion actualizada');
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _refrescando = false);
    }
  }

  Future<void> _cerrarSesion() async {
    final confirmado = await confirmar(
      context,
      titulo: 'Cerrar sesion',
      mensaje: 'Tendras que volver a ingresar tus credenciales.',
      textoConfirmar: 'Cerrar sesion',
      destructivo: true,
    );
    if (!confirmado || !mounted) return;
    context.read<CarritoService>().reiniciar();
    await context.read<AuthService>().cerrarSesion();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final usuario = auth.usuario;
    if (usuario == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi cuenta'),
        actions: [
          IconButton(
            tooltip: 'Actualizar permisos',
            onPressed: _refrescando ? null : _refrescarSesion,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Paleta.ink,
                child: Text(
                  usuario.nombre.characters.first.toUpperCase(),
                  style: const TextStyle(
                    color: Paleta.paper,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Titular(usuario.nombreCompleto, tamano: 22, mayusculas: false),
                    const SizedBox(height: 4),
                    Text(
                      usuario.email,
                      style: const TextStyle(color: Paleta.inkSuave, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        BadgeEstado(usuario.tipo, color: Paleta.ink),
                        if (usuario.rol != null) ...[
                          const SizedBox(width: 6),
                          BadgeEstado(usuario.rol!, color: Paleta.gold),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const EtiquetaDato('Mi actividad'),
          const SizedBox(height: 10),
          _Acceso(
            icono: Icons.receipt_long_outlined,
            titulo: 'Mis compras',
            detalle: 'Pedidos, pagos y comprobantes',
            alTocar: () => context.push('/mis-compras'),
          ),
          _Acceso(
            icono: Icons.event_available_outlined,
            titulo: 'Mis reservas',
            detalle: 'Prendas apartadas en el vestidor',
            alTocar: () => context.go('/mis-reservas'),
          ),
          if (!auth.esStaff) ...[
            _Acceso(
              icono: Icons.location_on_outlined,
              titulo: 'Mis direcciones',
              detalle: 'CU20 · Donde te llevamos los pedidos',
              alTocar: () => context.push('/mis-direcciones'),
            ),
            _Acceso(
              icono: Icons.chat_bubble_outline,
              titulo: 'Asistente',
              detalle: 'CU18 · Contale qué buscás y te sugiere prendas',
              alTocar: () => context.push('/asistente'),
            ),
          ],

          if (auth.esStaff) ...[
            const SizedBox(height: 26),
            const EtiquetaDato('Operacion de tienda'),
            const SizedBox(height: 10),
            _Acceso(
              icono: Icons.point_of_sale_outlined,
              titulo: 'Caja',
              detalle: 'CU07 · Registrar venta presencial',
              alTocar: () => context.push('/caja'),
            ),
            _Acceso(
              icono: Icons.checkroom_outlined,
              titulo: 'Atender reservas',
              detalle: 'CU08 · Cola de vestidores de la sucursal',
              alTocar: () => context.push('/atender-reservas'),
            ),
            if (auth.tienePermiso(const ['envios.leer', 'envios.actualizar']))
              _Acceso(
                icono: Icons.local_shipping_outlined,
                titulo: 'Envios a domicilio',
                detalle: 'CU20 · Hoja de ruta y estado de cada pedido',
                alTocar: () => context.push('/panel/envios'),
              ),
            _Acceso(
              icono: Icons.dashboard_outlined,
              titulo: 'Panel de gestion',
              detalle: 'CU09 a CU13 · Segun los permisos de tu rol',
              alTocar: () => context.push('/panel'),
            ),
            const SizedBox(height: 18),
            const EtiquetaDato('Permisos de tu rol'),
            const SizedBox(height: 8),
            if (auth.permisos.isEmpty)
              const Text(
                'Tu rol todavia no tiene permisos asignados.',
                style: TextStyle(color: Paleta.inkSuave, fontSize: 13),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: auth.permisos
                    .map((codigo) => BadgeEstado(codigo, color: Paleta.inkSuave))
                    .toList(),
              ),
          ],

          const SizedBox(height: 30),
          OutlinedButton.icon(
            onPressed: _cerrarSesion,
            style: OutlinedButton.styleFrom(
              foregroundColor: Paleta.rojo,
              side: const BorderSide(color: Paleta.rojo),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('CERRAR SESION'),
          ),
          const SizedBox(height: 18),
          Center(
            child: Column(
              children: [
                BadgeEstado(
                  Config.apuntaAProduccion ? 'RAILWAY' : 'LOCAL',
                  color: Config.apuntaAProduccion ? Paleta.verde : Paleta.gold,
                ),
                const SizedBox(height: 6),
                Text(
                  Config.apiUrl,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Paleta.inkSuave),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Acceso extends StatelessWidget {
  const _Acceso({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.alTocar,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TarjetaPanel(
          alTocar: alTocar,
          hijo: Row(
            children: [
              Icon(icono, color: Paleta.flame),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      detalle,
                      style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Paleta.inkSuave),
            ],
          ),
        ),
      );
}

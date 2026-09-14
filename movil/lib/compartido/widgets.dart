import 'package:flutter/material.dart';

import '../core/tema.dart';

/// Badge de estado, equivalente a los `.badge` de `panel-comun.css`.
class BadgeEstado extends StatelessWidget {
  const BadgeEstado(this.texto, {super.key, this.color});

  final String texto;
  final Color? color;

  static Color colorDeEstado(String estado) {
    switch (estado.toUpperCase()) {
      case 'CONFIRMADA':
      case 'PAGADA':
      case 'APROBADO':
      case 'COMPLETADA':
      case 'ACTIVA':
      case 'ABIERTA':
      case 'ENTREGADA':
      case 'CONVERTIDA':
      case 'ATENDIDA':
      case 'COMPRADO':
        return Paleta.verde;
      case 'PENDIENTE':
      case 'BORRADOR':
      case 'PREPARADA':
      case 'PREPARADO':
      case 'CLIENTE_PRESENTE':
      case 'RESERVADO':
      case 'PROBADO':
        return Paleta.gold;
      case 'ANULADA':
      case 'RECHAZADO':
      case 'CANCELADA':
      case 'EXPIRADA':
      case 'NO_PRESENTADO':
      case 'DESCARTADO':
      case 'FALLIDO':
        return Paleta.rojo;
      default:
        return Paleta.inkSuave;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? colorDeEstado(texto);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        border: Border.all(color: c.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto.replaceAll('_', ' ').toUpperCase(),
        style: fuenteMono(fontSize: 10.5, letterSpacing: 0.8, color: c),
      ),
    );
  }
}

/// Mensaje de error de la API con opcion de reintentar.
class MensajeError extends StatelessWidget {
  const MensajeError(this.mensaje, {super.key, this.alReintentar});

  final String mensaje;
  final VoidCallback? alReintentar;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Paleta.rojo.withValues(alpha: 0.08),
          border: Border.all(color: Paleta.rojo.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: Paleta.rojo, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(mensaje, style: const TextStyle(color: Paleta.rojo, height: 1.35)),
                ),
              ],
            ),
            if (alReintentar != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: alReintentar, child: const Text('Reintentar')),
              ),
          ],
        ),
      );
}

/// Estado vacio con icono y mensaje.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio({super.key, required this.mensaje, this.icono = Icons.inbox_outlined, this.accion});

  final String mensaje;
  final IconData icono;
  final Widget? accion;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 48, color: Paleta.paperLinea),
              const SizedBox(height: 14),
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Paleta.inkSuave, height: 1.4),
              ),
              if (accion != null) ...[const SizedBox(height: 18), accion!],
            ],
          ),
        ),
      );
}

/// Envoltorio que resuelve los tres estados de una pantalla que carga datos.
class VistaAsincrona extends StatelessWidget {
  const VistaAsincrona({
    super.key,
    required this.cargando,
    required this.error,
    required this.alReintentar,
    required this.hijo,
  });

  final bool cargando;
  final String? error;
  final VoidCallback alReintentar;
  final Widget hijo;

  @override
  Widget build(BuildContext context) {
    if (cargando) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: MensajeError(error!, alReintentar: alReintentar),
      );
    }
    return hijo;
  }
}

/// Tarjeta con el borde fino del vocabulario visual del panel.
class TarjetaPanel extends StatelessWidget {
  const TarjetaPanel({super.key, required this.hijo, this.padding, this.alTocar});

  final Widget hijo;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) => Material(
        color: Paleta.blanco,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: alTocar,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Paleta.paperLinea),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: padding ?? const EdgeInsets.all(14),
            child: hijo,
          ),
        ),
      );
}

/// Fila etiqueta/valor para los detalles.
class FilaDato extends StatelessWidget {
  const FilaDato(this.etiqueta, this.valor, {super.key, this.valorWidget});

  final String etiqueta;
  final String valor;
  final Widget? valorWidget;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 130, child: EtiquetaDato(etiqueta)),
            Expanded(
              child: valorWidget ??
                  Text(valor, style: const TextStyle(fontWeight: FontWeight.w500, height: 1.3)),
            ),
          ],
        ),
      );
}

void mostrarAviso(BuildContext context, String mensaje, {bool esError = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? Paleta.rojo : Paleta.ink,
        duration: const Duration(seconds: 3),
      ),
    );
}

Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String textoConfirmar = 'Confirmar',
  bool destructivo = false,
}) async {
  final resultado = await showDialog<bool>(
    context: context,
    builder: (contexto) => AlertDialog(
      backgroundColor: Paleta.blanco,
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(contexto, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(contexto, true),
          style: destructivo ? ElevatedButton.styleFrom(backgroundColor: Paleta.rojo) : null,
          child: Text(textoConfirmar),
        ),
      ],
    ),
  );
  return resultado ?? false;
}

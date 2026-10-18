import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuthService, } from '../../core/auth/auth.service';
import { PERMISO_ATENDER_RESERVAS, PERMISO_CAJA } from '../../core/auth/auth.guard';
import { ConexionService } from '../../core/offline/conexion.service';
import {
  AccionResolver,
  EstadoLocal,
  OperacionLocal,
  ProductoOffline,
  VarianteOffline,
} from '../../core/sincronizacion/sincronizacion.models';
import { LineaLocal, SincronizacionService, totalConIva } from '../../core/sincronizacion/sincronizacion.service';
import { interpretarError } from '../../shared/errores';
import { PanelShell } from '../../shared/panel/panel-shell';

interface LineaCarrito extends LineaLocal {
  producto: string;
  variante: VarianteOffline;
}

/** a partir de cuantas horas se avisa que las existencias pueden haber cambiado */
const HORAS_DESACTUALIZADO = 2;

const ETIQUETA_ESTADO: Record<EstadoLocal, string> = {
  REGISTRADA: 'Solo en este equipo',
  ENVIADA: 'Enviada, sin respuesta',
  CONFIRMADA: 'Confirmada',
  RECHAZADA: 'Rechazada',
  CONFLICTO: 'En conflicto',
};

/**
 * Operacion sin conexion de la PWA (Modulo B: CU13 a CU20). El personal baja el catalogo de su
 * sucursal, vende de contado y registra reservas sin red; todo queda en IndexedDB con su UUID y
 * se sincroniza solo al volver la conexion. La pantalla muestra en todo momento cuantas
 * operaciones esperan, como quedo cada una y si lo que se ve puede estar desactualizado.
 */
@Component({
  selector: 'app-venta-offline-page',
  standalone: true,
  imports: [PanelShell, FormsModule],
  templateUrl: './venta-offline.page.html',
  styleUrls: ['../../shared/panel/panel-comun.css', './venta-offline.page.css'],
})
export class VentaOfflinePage implements OnInit {
  protected readonly sync = inject(SincronizacionService);
  protected readonly conexion = inject(ConexionService);
  protected readonly auth = inject(AuthService);

  protected readonly puedeVender = this.auth.tienePermiso(PERMISO_CAJA);
  protected readonly puedeReservar = this.auth.tienePermiso(PERMISO_ATENDER_RESERVAS);
  protected readonly gestionaConflictos = this.auth.tienePermiso('sincronizacion.actualizar');
  protected readonly sinOffline = !this.auth.tieneFuncion('operacion_offline');

  protected solapa: 'vender' | 'reservar' | 'operaciones' = this.puedeVender ? 'vender' : 'reservar';
  protected busqueda = signal('');
  protected readonly carrito = signal<LineaCarrito[]>([]);
  protected montoRecibido: number | null = null;
  protected clienteVenta = '';
  protected clienteReserva = '';
  protected fechaVisita = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
  protected horaVisita = '11:00';
  protected observaciones = '';

  protected readonly ocupado = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);

  protected readonly etiquetas = ETIQUETA_ESTADO;

  protected readonly productos = computed<ProductoOffline[]>(() => {
    const q = this.busqueda().trim().toLowerCase();
    const todos = this.sync.paquete()?.productos ?? [];
    return (q
      ? todos.filter((p) => `${p.nombre} ${p.codigo} ${p.categoria} ${p.variantes.map((v) => v.sku).join(' ')}`.toLowerCase().includes(q))
      : todos
    ).slice(0, 40);
  });

  protected readonly total = computed(() =>
    totalConIva(this.carrito().map((l) => ({ precio: l.variante.precio, cantidad: l.cantidad })), this.sync.paquete()?.iva_tasa),
  );

  protected readonly desactualizado = computed(() => {
    const de = this.sync.paqueteDe();
    if (!de) return false;
    return !this.conexion.enLinea() || Date.now() - new Date(de).getTime() > HORAS_DESACTUALIZADO * 3_600_000;
  });

  ngOnInit(): void {
    void this.sync.cargarLocal().then(() => {
      if (!this.sync.paquete() && this.conexion.enLinea()) void this.descargar();
    });
  }

  protected async descargar(): Promise<void> {
    await this.correr(async () => {
      const p = await this.sync.descargarPaquete();
      this.aviso.set(`Catálogo de ${p.sucursal.nombre} descargado: ${p.productos.length} prendas y ${p.clientes.length} clientas.`);
    });
  }

  protected agregar(producto: ProductoOffline, variante: VarianteOffline): void {
    this.error.set(null);
    const ya = this.carrito().find((l) => l.variante_id === variante.id);
    const cantidad = (ya?.cantidad ?? 0) + 1;
    if (cantidad > variante.disponible) {
      this.error.set(`De ${variante.sku} hay ${variante.disponible} unidad(es) conocidas en la sucursal.`);
      return;
    }
    this.carrito.update((lineas) =>
      ya
        ? lineas.map((l) => (l.variante_id === variante.id ? { ...l, cantidad } : l))
        : [...lineas, { variante_id: variante.id, cantidad: 1, producto: producto.nombre, variante }],
    );
  }

  protected cambiarCantidad(linea: LineaCarrito, delta: number): void {
    const cantidad = linea.cantidad + delta;
    this.carrito.update((lineas) =>
      cantidad <= 0
        ? lineas.filter((l) => l !== linea)
        : lineas.map((l) => (l === linea ? { ...l, cantidad: Math.min(cantidad, l.variante.disponible) } : l)),
    );
  }

  protected vuelto(): number | null {
    return this.montoRecibido !== null && this.montoRecibido >= this.total() ? this.montoRecibido - this.total() : null;
  }

  protected async registrarVenta(): Promise<void> {
    if (this.montoRecibido !== null && this.montoRecibido < this.total()) {
      this.error.set('El efectivo recibido no alcanza para el total.');
      return;
    }
    await this.correr(async () => {
      const op = await this.sync.registrarVenta(this.lineas(), this.montoRecibido, this.clienteVenta.trim() || null);
      this.limpiarCarrito();
      this.aviso.set(
        `Venta de Bs ${op.total.toFixed(2)} registrada${this.conexion.enLinea() ? ' y enviada' : ' en este equipo: se sincroniza al volver la red'}.`,
      );
    });
  }

  protected async registrarReserva(): Promise<void> {
    if (!this.clienteReserva.trim()) {
      this.error.set('Elegí la clienta de la reserva.');
      return;
    }
    await this.correr(async () => {
      await this.sync.registrarReserva(
        this.lineas().map(({ variante_id, cantidad }) => ({ variante_id, cantidad })),
        this.clienteReserva.trim(),
        this.fechaVisita,
        this.horaVisita,
        this.observaciones.trim() || null,
      );
      this.limpiarCarrito();
      this.aviso.set('Reserva registrada: compromete las prendas apenas el servidor la confirme.');
    });
  }

  protected async sincronizar(): Promise<void> {
    await this.correr(() => this.sync.sincronizar());
  }

  protected async resolver(o: OperacionLocal, accion: AccionResolver): Promise<void> {
    let nota: string | undefined;
    if (accion === 'DESCARTAR') {
      nota = prompt('¿Por qué se descarta? (por ejemplo: se devolvió el efectivo a la clienta)') ?? undefined;
      if (nota === undefined) return;
    }
    await this.correr(async () => {
      await this.sync.resolver(o.id, accion, nota);
      this.aviso.set('Operación actualizada.');
    });
  }

  protected async refrescar(o: OperacionLocal): Promise<void> {
    await this.correr(() => this.sync.refrescar(o.id));
  }

  protected async archivar(): Promise<void> {
    const n = await this.sync.archivarCerradas();
    this.aviso.set(`${n} operación(es) cerradas se quitaron de este equipo (siguen en el servidor).`);
  }

  protected fecha(valor: string | null): string {
    return valor ? new Date(valor).toLocaleString('es-BO') : '—';
  }

  protected numeroDe(o: OperacionLocal): string | null {
    const r = o.respuesta?.resultado;
    return (r?.['numero'] as string) ?? (r?.['codigo'] as string) ?? null;
  }

  private lineas(): LineaLocal[] {
    return this.carrito().map(({ variante_id, cantidad }) => ({ variante_id, cantidad }));
  }

  private limpiarCarrito(): void {
    this.carrito.set([]);
    this.montoRecibido = null;
    this.clienteVenta = '';
    this.observaciones = '';
  }

  private async correr(accion: () => Promise<unknown>): Promise<void> {
    this.ocupado.set(true);
    this.error.set(null);
    this.aviso.set(null);
    try {
      await accion();
    } catch (e) {
      this.error.set(e instanceof HttpErrorResponse ? interpretarError(e) : (e as Error).message);
    } finally {
      this.ocupado.set(false);
    }
  }
}

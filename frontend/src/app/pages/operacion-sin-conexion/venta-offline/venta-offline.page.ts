import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuthService, } from '../../../core/acceso-y-organizacion/auth/auth.service';
import { PERMISO_ATENDER_RESERVAS, PERMISO_CAJA } from '../../../core/acceso-y-organizacion/auth/auth.guard';
import { ConexionService } from '../../../core/operacion-sin-conexion/offline/conexion.service';
import {
  AccionResolver,
  EstadoLocal,
  OperacionLocal,
  ProductoOffline,
  VarianteOffline,
} from '../../../core/operacion-sin-conexion/sincronizacion/sincronizacion.models';
import { LineaLocal, SincronizacionService, totalConIva } from '../../../core/operacion-sin-conexion/sincronizacion/sincronizacion.service';
import { interpretarError } from '../../../shared/errores';
import { PanelShell } from '../../../shared/panel/panel-shell';

interface LineaCarrito extends LineaLocal {
  producto: string;
  variante: VarianteOffline;
}

/** a partir de cuantas horas se avisa que las existencias pueden haber cambiado */
const HORAS_DESACTUALIZADO = 2;

/** tope de prendas que se dibujan a la vez; la busqueda sigue recorriendo todo el catalogo */
const LIMITE_PRENDAS = 40;

const ETIQUETA_ESTADO: Record<EstadoLocal, string> = {
  REGISTRADA: 'Solo en este equipo',
  ENVIADA: 'Enviada, sin respuesta',
  CONFIRMADA: 'Confirmada',
  RECHAZADA: 'Rechazada',
  CONFLICTO: 'En conflicto',
};

/**
 * Operacion sin conexion de la PWA (Modulo B: CU17 a CU21). El personal baja el catalogo de su
 * sucursal, vende de contado y registra reservas sin red; todo queda en IndexedDB con su UUID y
 * se sincroniza solo al volver la conexion. La pantalla muestra en todo momento cuantas
 * operaciones esperan, como quedo cada una y si lo que se ve puede estar desactualizado.
 */
@Component({
  selector: 'app-venta-offline-page',
  standalone: true,
  imports: [PanelShell, FormsModule],
  templateUrl: './venta-offline.page.html',
  styleUrls: ['../../../shared/panel/panel-comun.css', './venta-offline.page.css'],
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

  /** Prendas que coinciden con la busqueda: todas las palabras escritas tienen que aparecer (nombre, codigo, categoria, SKU, talla o color). */
  private readonly coincidencias = computed<ProductoOffline[]>(() => {
    const palabras = this.busqueda().trim().toLowerCase().split(/\s+/).filter(Boolean);
    const todos = this.sync.paquete()?.productos ?? [];
    if (palabras.length === 0) return todos;
    return todos.filter((p) => {
      const texto = [
        p.nombre,
        p.codigo,
        p.categoria,
        ...p.variantes.flatMap((v) => [v.sku, v.talla, v.color]),
      ]
        .join(' ')
        .toLowerCase();
      return palabras.every((palabra) => texto.includes(palabra));
    });
  });

  protected readonly productos = computed<ProductoOffline[]>(() => this.coincidencias().slice(0, LIMITE_PRENDAS));
  protected readonly totalCoincidencias = computed(() => this.coincidencias().length);
  protected readonly totalCatalogo = computed(() => this.sync.paquete()?.productos.length ?? 0);

  /** Variantes de una prenda agrupadas por color, para mostrar "Negro: S M L" en vez de una tira de botones iguales. */
  protected porColor(p: ProductoOffline): { color: string; hex: string; variantes: VarianteOffline[] }[] {
    const grupos = new Map<string, { color: string; hex: string; variantes: VarianteOffline[] }>();
    for (const v of p.variantes) {
      const grupo = grupos.get(v.color) ?? { color: v.color, hex: v.codigo_hex, variantes: [] };
      grupo.variantes.push(v);
      grupos.set(v.color, grupo);
    }
    return [...grupos.values()];
  }

  /** Prendas cuya foto no cargo (sin red y sin cache): se dibuja la inicial sobre el color. */
  protected readonly imagenFallida = signal<ReadonlySet<string>>(new Set());

  protected marcarImagenFallida(id: string): void {
    this.imagenFallida.update((s) => new Set(s).add(id));
  }

  protected unidades(p: ProductoOffline): number {
    return p.variantes.reduce((suma, v) => suma + v.disponible, 0);
  }

  protected desde(p: ProductoOffline): number {
    return p.variantes.length ? Math.min(...p.variantes.map((v) => v.precio)) : p.precio_base;
  }

  /** Cuantas unidades de esa variante ya estan en el carrito de esta pantalla. */
  protected enCarrito(v: VarianteOffline): number {
    return this.carrito().find((l) => l.variante_id === v.id)?.cantidad ?? 0;
  }

  protected readonly busquedaOp = signal('');

  /** Operaciones de este equipo, mas recientes primero, filtradas por id, descripcion, estado o numero generado. */
  protected readonly operacionesVisibles = computed<OperacionLocal[]>(() => {
    const q = this.busquedaOp().trim().toLowerCase();
    const lista = [...this.sync.operaciones()].sort(
      (a, b) => new Date(b.op.registrada_en).getTime() - new Date(a.op.registrada_en).getTime(),
    );
    if (!q) return lista;
    return lista.filter((o) =>
      [o.id, o.descripcion, ETIQUETA_ESTADO[o.estado], o.respuesta?.motivo, o.respuesta?.codigo_motivo, this.numeroDe(o)]
        .filter(Boolean)
        .join(' ')
        .toLowerCase()
        .includes(q),
    );
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

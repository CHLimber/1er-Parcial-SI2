import { Injectable, computed, signal } from '@angular/core';

const STORAGE_KEY = 'fashionstore.reserva_carrito';

export interface ItemCarritoReserva {
  varianteId: string;
  sku: string;
  producto: string;
  productoSlug: string;
  talla: string;
  color: string;
  codigoHex: string;
  precio: number;
  imagenUrl: string | null;
  cantidad: number;
}

@Injectable({ providedIn: 'root' })
export class ReservaCarritoService {
  private readonly itemsSignal = signal<ItemCarritoReserva[]>(this.leerGuardado());

  readonly items = this.itemsSignal.asReadonly();
  readonly cantidadTotal = computed(() =>
    this.itemsSignal().reduce((total, item) => total + item.cantidad, 0),
  );

  agregar(item: ItemCarritoReserva): void {
    this.itemsSignal.update((actuales) => {
      const existente = actuales.find((i) => i.varianteId === item.varianteId);
      const siguientes = existente
        ? actuales.map((i) =>
            i.varianteId === item.varianteId ? { ...i, cantidad: i.cantidad + item.cantidad } : i,
          )
        : [...actuales, item];
      this.guardar(siguientes);
      return siguientes;
    });
  }

  actualizarCantidad(varianteId: string, cantidad: number): void {
    this.itemsSignal.update((actuales) => {
      const siguientes = actuales.map((i) => (i.varianteId === varianteId ? { ...i, cantidad } : i));
      this.guardar(siguientes);
      return siguientes;
    });
  }

  quitar(varianteId: string): void {
    this.itemsSignal.update((actuales) => {
      const siguientes = actuales.filter((i) => i.varianteId !== varianteId);
      this.guardar(siguientes);
      return siguientes;
    });
  }

  limpiar(): void {
    this.itemsSignal.set([]);
    localStorage.removeItem(STORAGE_KEY);
  }

  private guardar(items: ItemCarritoReserva[]): void {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(items));
  }

  private leerGuardado(): ItemCarritoReserva[] {
    const crudo = localStorage.getItem(STORAGE_KEY);
    if (!crudo) return [];
    try {
      return JSON.parse(crudo) as ItemCarritoReserva[];
    } catch {
      localStorage.removeItem(STORAGE_KEY);
      return [];
    }
  }
}

import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuthService } from '../../core/auth/auth.service';
import {
  AjusteOut,
  MovimientoKardexOut,
  VarianteBuscadaOut,
} from '../../core/inventario/inventario.models';
import { InventarioService } from '../../core/inventario/inventario.service';
import { SucursalOut } from '../../core/sucursales/sucursales.models';
import { SucursalesService } from '../../core/sucursales/sucursales.service';
import { interpretarError } from '../../shared/errores';
import { PanelShell } from '../../shared/panel/panel-shell';

/** Ajustes manuales de stock (PENDIENTES.txt 2.6): buscador + kardex + formulario de ajuste. */
@Component({
  selector: 'app-panel-inventario-page',
  standalone: true,
  imports: [PanelShell, FormsModule, DatePipe],
  templateUrl: './panel-inventario.page.html',
  styleUrls: ['../../shared/panel/panel-comun.css', './panel-inventario.page.css'],
})
export class PanelInventarioPage implements OnInit {
  private readonly servicio = inject(InventarioService);
  private readonly sucursalesService = inject(SucursalesService);
  private readonly auth = inject(AuthService);

  protected readonly puedeAjustar = this.auth.tienePermiso('inventario.actualizar');
  protected readonly eligeSucursal = this.auth.tienePermiso('sucursales.actualizar');

  protected readonly sucursales = signal<SucursalOut[]>([]);
  protected sucursalId = '';

  protected termino = '';
  protected readonly resultados = signal<VarianteBuscadaOut[]>([]);
  protected readonly buscando = signal(false);
  protected readonly errorBusqueda = signal<string | null>(null);

  protected readonly elegida = signal<VarianteBuscadaOut | null>(null);
  protected readonly kardex = signal<MovimientoKardexOut[]>([]);
  protected readonly cargandoKardex = signal(false);

  protected cantidadNueva: number | null = null;
  protected motivo = '';
  protected readonly guardando = signal(false);
  protected readonly errorAjuste = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);

  ngOnInit(): void {
    // Sin sucursales.actualizar el backend resuelve solo la sucursal del staff (no la
    // conocemos en el frontend, UsuarioOut no la expone) -- no hace falta el selector.
    if (!this.eligeSucursal) return;

    this.sucursalesService.listarSucursales().subscribe({
      next: (sucursales) => {
        this.sucursales.set(sucursales);
        this.sucursalId = sucursales[0]?.id ?? '';
      },
      error: () => this.sucursales.set([]),
    });
  }

  protected cambiarSucursal(): void {
    this.resultados.set([]);
    this.limpiarSeleccion();
  }

  protected buscar(): void {
    if (!this.termino.trim()) return;

    this.buscando.set(true);
    this.errorBusqueda.set(null);
    this.servicio.buscarVariantes(this.termino.trim(), this.sucursalId || null).subscribe({
      next: (resultados) => {
        this.resultados.set(resultados);
        this.buscando.set(false);
      },
      error: (e: HttpErrorResponse) => {
        this.buscando.set(false);
        this.errorBusqueda.set(interpretarError(e, 'No se pudo buscar en el inventario.'));
      },
    });
  }

  protected elegir(variante: VarianteBuscadaOut): void {
    this.elegida.set(variante);
    this.errorAjuste.set(null);
    this.aviso.set(null);
    this.cantidadNueva = variante.cantidad_fisica;
    this.motivo = '';
    this.cargarKardex(variante);
  }

  private cargarKardex(variante: VarianteBuscadaOut): void {
    this.cargandoKardex.set(true);
    this.servicio.kardex(variante.id, variante.sucursal_id).subscribe({
      next: (movimientos) => {
        this.kardex.set(movimientos);
        this.cargandoKardex.set(false);
      },
      error: () => {
        this.kardex.set([]);
        this.cargandoKardex.set(false);
      },
    });
  }

  protected limpiarSeleccion(): void {
    this.elegida.set(null);
    this.kardex.set([]);
    this.cantidadNueva = null;
    this.motivo = '';
    this.errorAjuste.set(null);
    this.aviso.set(null);
  }

  protected guardarAjuste(): void {
    const variante = this.elegida();
    if (!variante) return;

    if (this.cantidadNueva == null || this.cantidadNueva <= 0) {
      this.errorAjuste.set('La cantidad física nueva tiene que ser mayor a cero.');
      return;
    }
    if (this.motivo.trim().length < 3) {
      this.errorAjuste.set('Contá el motivo del ajuste (mínimo 3 caracteres).');
      return;
    }

    this.guardando.set(true);
    this.errorAjuste.set(null);
    this.aviso.set(null);
    this.servicio
      .ajustar({
        sucursal_id: variante.sucursal_id,
        variante_id: variante.id,
        cantidad_fisica_nueva: Math.round(this.cantidadNueva),
        motivo: this.motivo.trim(),
      })
      .subscribe({
        next: (resultado: AjusteOut) => {
          this.guardando.set(false);
          this.aviso.set(
            `Ajuste registrado: ${resultado.saldo_anterior} → ${resultado.saldo_nuevo} unidades.`,
          );
          const actualizada: VarianteBuscadaOut = {
            ...variante,
            cantidad_fisica: resultado.saldo_nuevo,
            disponible: resultado.saldo_nuevo - variante.cantidad_reservada,
          };
          this.elegida.set(actualizada);
          this.resultados.update((filas) =>
            filas.map((fila) => (fila.id === actualizada.id ? actualizada : fila)),
          );
          this.motivo = '';
          this.cantidadNueva = resultado.saldo_nuevo;
          this.cargarKardex(actualizada);
        },
        error: (e: HttpErrorResponse) => {
          this.guardando.set(false);
          this.errorAjuste.set(interpretarError(e));
        },
      });
  }

  protected etiquetaMovimiento(tipo: string): string {
    const etiquetas: Record<string, string> = {
      ENTRADA: 'Entrada',
      SALIDA: 'Salida',
      RESERVA: 'Reserva',
      LIBERACION: 'Liberación',
      AJUSTE: 'Ajuste',
      TRASPASO_SALIDA: 'Traspaso (salida)',
      TRASPASO_ENTRADA: 'Traspaso (entrada)',
    };
    return etiquetas[tipo] ?? tipo;
  }
}

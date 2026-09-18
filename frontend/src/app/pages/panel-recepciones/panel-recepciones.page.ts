import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormBuilder, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';

import { AuthService } from '../../core/auth/auth.service';
import { ProveedorOut } from '../../core/proveedores/proveedores.models';
import { ProveedoresService } from '../../core/proveedores/proveedores.service';
import {
  DetalleOut,
  EstadoRecepcion,
  MovimientoOut,
  RecepcionDetalleOut,
  RecepcionOut,
  VarianteBuscadaOut,
} from '../../core/recepciones/recepciones.models';
import { RecepcionesService } from '../../core/recepciones/recepciones.service';
import { SucursalOut } from '../../core/sucursales/sucursales.models';
import { SucursalesService } from '../../core/sucursales/sucursales.service';
import { interpretarError } from '../../shared/errores';
import { PanelShell } from '../../shared/panel/panel-shell';

/** CU09 - Registrar Recepcion de Mercaderia. */
@Component({
  selector: 'app-panel-recepciones-page',
  standalone: true,
  imports: [PanelShell, ReactiveFormsModule, FormsModule],
  templateUrl: './panel-recepciones.page.html',
  styleUrls: ['../../shared/panel/panel-comun.css', './panel-recepciones.page.css'],
})
export class PanelRecepcionesPage implements OnInit {
  private readonly servicio = inject(RecepcionesService);
  private readonly proveedoresService = inject(ProveedoresService);
  private readonly sucursalesService = inject(SucursalesService);
  private readonly fb = inject(FormBuilder);
  private readonly auth = inject(AuthService);

  protected readonly puedeRegistrar = this.auth.tienePermiso(
    'recepciones.crear',
    'recepciones.actualizar',
    'recepciones.eliminar',
  );
  protected readonly puedeConfirmar = this.auth.tienePermiso(
    'recepciones.actualizar',
    'recepciones.eliminar',
  );
  protected readonly eligeSucursal = this.auth.tienePermiso('sucursales.actualizar');

  protected readonly cargando = signal(true);
  protected readonly recepciones = signal<RecepcionOut[]>([]);
  protected readonly error = signal<string | null>(null);
  protected filtroEstado: '' | EstadoRecepcion = '';

  protected readonly proveedores = signal<ProveedorOut[]>([]);
  protected readonly sucursales = signal<SucursalOut[]>([]);

  protected readonly seleccionada = signal<RecepcionDetalleOut | null>(null);
  protected readonly movimientos = signal<MovimientoOut[]>([]);
  protected readonly errorDetalle = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);
  protected readonly ocupado = signal(false);

  protected readonly creando = signal(false);
  protected readonly errorNueva = signal<string | null>(null);

  // --- buscador de variantes ---
  protected termino = '';
  protected readonly resultados = signal<VarianteBuscadaOut[]>([]);
  protected readonly buscando = signal(false);
  protected readonly elegida = signal<VarianteBuscadaOut | null>(null);
  protected cantidad = 1;
  protected costo = 0;

  protected readonly lineaEditada = signal<DetalleOut | null>(null);

  protected readonly formNueva = this.fb.nonNullable.group({
    proveedor_id: ['', [Validators.required]],
    sucursal_id: [''],
    numero: [''],
    fecha: [''],
  });

  ngOnInit(): void {
    this.cargar();
    this.proveedoresService.listar(undefined, true).subscribe({
      next: (proveedores) => this.proveedores.set(proveedores),
      error: () => this.proveedores.set([]),
    });
    this.sucursalesService.listarSucursales().subscribe({
      next: (sucursales) => this.sucursales.set(sucursales),
      error: () => this.sucursales.set([]),
    });
  }

  protected cargar(): void {
    this.cargando.set(true);
    this.error.set(null);
    this.servicio.listar(this.filtroEstado || null).subscribe({
      next: (recepciones) => {
        this.recepciones.set(recepciones);
        this.cargando.set(false);
      },
      error: (e: HttpErrorResponse) => {
        this.error.set(interpretarError(e, 'No se pudieron cargar las recepciones.'));
        this.cargando.set(false);
      },
    });
  }

  protected abrirNueva(): void {
    this.creando.set(true);
    this.errorNueva.set(null);
    this.seleccionada.set(null);
    this.formNueva.reset({
      proveedor_id: this.proveedores()[0]?.id ?? '',
      sucursal_id: this.sucursales()[0]?.id ?? '',
      numero: '',
      fecha: '',
    });
  }

  protected crear(): void {
    if (this.formNueva.invalid) {
      this.formNueva.markAllAsTouched();
      return;
    }

    const crudo = this.formNueva.getRawValue();
    this.ocupado.set(true);
    this.errorNueva.set(null);
    this.servicio
      .crear({
        proveedor_id: crudo.proveedor_id,
        sucursal_id: this.eligeSucursal ? crudo.sucursal_id || null : null,
        numero: crudo.numero.trim() || null,
        fecha: crudo.fecha || null,
      })
      .subscribe({
        next: (recepcion) => {
          this.ocupado.set(false);
          this.creando.set(false);
          this.aplicar(recepcion);
          this.cargar();
        },
        error: (e: HttpErrorResponse) => {
          this.ocupado.set(false);
          this.errorNueva.set(interpretarError(e));
        },
      });
  }

  protected abrir(recepcion: RecepcionOut): void {
    this.creando.set(false);
    this.errorDetalle.set(null);
    this.aviso.set(null);
    this.servicio.obtener(recepcion.id).subscribe({
      next: (detalle) => this.aplicar(detalle),
      error: (e: HttpErrorResponse) => this.errorDetalle.set(interpretarError(e)),
    });
  }

  private aplicar(detalle: RecepcionDetalleOut): void {
    this.seleccionada.set(detalle);
    this.limpiarBuscador();
    this.movimientos.set([]);
    if (detalle.estado === 'CONFIRMADA') this.cargarMovimientos(detalle.id);
  }

  private cargarMovimientos(id: string): void {
    this.servicio.movimientos(id).subscribe({
      next: (movimientos) => this.movimientos.set(movimientos),
      error: () => this.movimientos.set([]),
    });
  }

  protected limpiarBuscador(): void {
    this.termino = '';
    this.resultados.set([]);
    this.elegida.set(null);
    this.lineaEditada.set(null);
    this.cantidad = 1;
    this.costo = 0;
  }

  protected buscar(): void {
    const recepcion = this.seleccionada();
    if (!recepcion || !this.termino.trim()) return;

    this.buscando.set(true);
    this.errorDetalle.set(null);
    this.servicio.buscarVariantes(this.termino.trim(), recepcion.sucursal_id).subscribe({
      next: (resultados) => {
        this.resultados.set(resultados);
        this.buscando.set(false);
      },
      error: (e: HttpErrorResponse) => {
        this.buscando.set(false);
        this.errorDetalle.set(interpretarError(e));
      },
    });
  }

  protected elegir(variante: VarianteBuscadaOut): void {
    this.elegida.set(variante);
    this.lineaEditada.set(null);
    this.cantidad = 1;
    this.costo = Number(variante.precio_base);
  }

  protected editarLinea(linea: DetalleOut): void {
    this.lineaEditada.set(linea);
    this.elegida.set(null);
    this.cantidad = linea.cantidad;
    this.costo = Number(linea.costo_unitario);
  }

  protected agregar(): void {
    const recepcion = this.seleccionada();
    const variante = this.elegida();
    if (!recepcion || !variante) return;

    if (this.cantidad <= 0) {
      this.errorDetalle.set('La cantidad recibida debe ser mayor a cero.');
      return;
    }

    this.ocupado.set(true);
    this.errorDetalle.set(null);
    this.servicio
      .agregarLinea(recepcion.id, {
        variante_id: variante.id,
        cantidad: Number(this.cantidad),
        costo_unitario: Number(this.costo),
      })
      .subscribe({
        next: (detalle) => {
          this.ocupado.set(false);
          this.aplicar(detalle);
          this.cargar();
        },
        error: (e: HttpErrorResponse) => {
          this.ocupado.set(false);
          this.errorDetalle.set(interpretarError(e));
        },
      });
  }

  protected guardarLinea(): void {
    const recepcion = this.seleccionada();
    const linea = this.lineaEditada();
    if (!recepcion || !linea) return;

    this.ocupado.set(true);
    this.errorDetalle.set(null);
    this.servicio
      .editarLinea(recepcion.id, linea.id, {
        variante_id: linea.variante_id,
        cantidad: Number(this.cantidad),
        costo_unitario: Number(this.costo),
      })
      .subscribe({
        next: (detalle) => {
          this.ocupado.set(false);
          this.aplicar(detalle);
          this.cargar();
        },
        error: (e: HttpErrorResponse) => {
          this.ocupado.set(false);
          this.errorDetalle.set(interpretarError(e));
        },
      });
  }

  protected quitarLinea(linea: DetalleOut): void {
    const recepcion = this.seleccionada();
    if (!recepcion) return;

    this.ocupado.set(true);
    this.errorDetalle.set(null);
    this.servicio.quitarLinea(recepcion.id, linea.id).subscribe({
      next: (detalle) => {
        this.ocupado.set(false);
        this.aplicar(detalle);
        this.cargar();
      },
      error: (e: HttpErrorResponse) => {
        this.ocupado.set(false);
        this.errorDetalle.set(interpretarError(e));
      },
    });
  }

  protected confirmar(): void {
    const recepcion = this.seleccionada();
    if (!recepcion) return;

    this.ocupado.set(true);
    this.errorDetalle.set(null);
    this.aviso.set(null);
    this.servicio.confirmar(recepcion.id).subscribe({
      next: (detalle) => {
        this.ocupado.set(false);
        this.aplicar(detalle);
        this.aviso.set(
          `Recepción ${detalle.numero} confirmada: ${detalle.unidades} unidad(es) entraron al stock de ${detalle.sucursal}.`,
        );
        this.cargar();
      },
      error: (e: HttpErrorResponse) => {
        this.ocupado.set(false);
        this.errorDetalle.set(interpretarError(e));
      },
    });
  }

  protected anular(): void {
    const recepcion = this.seleccionada();
    if (!recepcion) return;

    this.ocupado.set(true);
    this.errorDetalle.set(null);
    this.servicio.anular(recepcion.id).subscribe({
      next: (detalle) => {
        this.ocupado.set(false);
        this.aplicar(detalle);
        this.cargar();
      },
      error: (e: HttpErrorResponse) => {
        this.ocupado.set(false);
        this.errorDetalle.set(interpretarError(e));
      },
    });
  }

  protected get totalCargado(): number {
    return (this.seleccionada()?.detalle ?? []).reduce((suma, linea) => suma + Number(linea.subtotal), 0);
  }

  protected precio(valor: number | null | undefined): string {
    return valor === null || valor === undefined ? '—' : `Bs ${Number(valor).toFixed(2)}`;
  }

  protected etiquetaEstado(estado: EstadoRecepcion): string {
    switch (estado) {
      case 'BORRADOR':
        return 'Borrador';
      case 'CONFIRMADA':
        return 'Confirmada';
      case 'ANULADA':
        return 'Anulada';
    }
  }
}

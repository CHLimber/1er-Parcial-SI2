import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuthService } from '../../core/auth/auth.service';
import { ClienteTenantOut, PerfilClienteIn, SEGMENTOS, Segmento } from '../../core/clientes/clientes.models';
import { ClientesService } from '../../core/clientes/clientes.service';
import { SucursalOut } from '../../core/sucursales/sucursales.models';
import { SucursalesService } from '../../core/sucursales/sucursales.service';
import { interpretarError } from '../../shared/errores';
import { PanelShell } from '../../shared/panel/panel-shell';

/**
 * Cartera de clientas de la sucursal (Segundo parcial, PENDIENTES 5.7): "cada administracion
 * podra hacer el perfil de sus clientes". La lista sale del historial de compras/reservas en la
 * sucursal mas las altas a mano; la ficha (segmento, talla, estilo, notas) es de esta sucursal y
 * no la ven las otras. El ADMIN elige la sucursal; el encargado ve siempre la suya.
 */
@Component({
  selector: 'app-panel-clientes-page',
  standalone: true,
  imports: [PanelShell, FormsModule],
  templateUrl: './panel-clientes.page.html',
  styleUrls: [
    '../../shared/panel/panel-comun.css',
    '../panel-recepciones/panel-recepciones.page.css',
    './panel-clientes.page.css',
  ],
})
export class PanelClientesPage implements OnInit {
  private readonly servicio = inject(ClientesService);
  private readonly sucursalesService = inject(SucursalesService);
  private readonly auth = inject(AuthService);

  protected readonly puedeEditar = this.auth.tienePermiso('clientes.actualizar');
  protected readonly eligeSucursal = this.auth.tienePermiso('sucursales.actualizar');
  protected readonly segmentos = SEGMENTOS;

  protected readonly sucursales = signal<SucursalOut[]>([]);
  protected sucursalId = '';
  protected busqueda = '';
  protected filtroSegmento: '' | Segmento = '';

  protected readonly clientes = signal<ClienteTenantOut[]>([]);
  protected readonly cargando = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);
  protected readonly ocupado = signal(false);

  protected readonly seleccionada = signal<ClienteTenantOut | null>(null);
  protected readonly agregando = signal(false);
  protected emailNueva = '';
  protected perfil: PerfilClienteIn = this.perfilVacio();

  ngOnInit(): void {
    if (this.eligeSucursal) {
      this.sucursalesService.listarSucursales().subscribe({
        next: (sucursales) => this.sucursales.set(sucursales),
      });
    }
    this.cargar();
  }

  private perfilVacio(): PerfilClienteIn {
    return {
      segmento: null,
      talla_habitual: null,
      estilo_preferido: null,
      telefono_contacto: null,
      acepta_whatsapp: false,
      notas: null,
    };
  }

  protected cargar(): void {
    this.cargando.set(true);
    this.error.set(null);
    this.servicio
      .listar(this.sucursalId || null, this.busqueda.trim() || null, this.filtroSegmento || null)
      .subscribe({
        next: (clientes) => {
          this.clientes.set(clientes);
          this.cargando.set(false);
        },
        error: (e: HttpErrorResponse) => {
          this.error.set(interpretarError(e, 'No se pudo cargar la cartera de clientas.'));
          this.cargando.set(false);
        },
      });
  }

  protected abrir(cliente: ClienteTenantOut): void {
    this.agregando.set(false);
    this.aviso.set(null);
    this.seleccionada.set(cliente);
    this.perfil = {
      segmento: cliente.tiene_perfil ? cliente.segmento : null,
      talla_habitual: cliente.talla_habitual,
      estilo_preferido: cliente.estilo_preferido,
      telefono_contacto: cliente.telefono_contacto,
      acepta_whatsapp: cliente.acepta_whatsapp,
      notas: cliente.notas,
    };
  }

  protected abrirAlta(): void {
    this.seleccionada.set(null);
    this.agregando.set(true);
    this.aviso.set(null);
    this.emailNueva = '';
    this.perfil = this.perfilVacio();
  }

  protected guardar(): void {
    const cliente = this.seleccionada();
    const datos = { ...this.perfil, segmento: this.perfil.segmento || null };
    this.ocupado.set(true);
    this.error.set(null);
    const pedido = cliente
      ? this.servicio.editarPerfil(cliente.usuario_id, datos, this.sucursalId || null)
      : this.servicio.agregar({ ...datos, email: this.emailNueva.trim() }, this.sucursalId || null);
    pedido.subscribe({
      next: (guardada) => {
        this.ocupado.set(false);
        this.agregando.set(false);
        this.seleccionada.set(guardada);
        this.aviso.set(`Ficha de ${guardada.nombre} guardada.`);
        this.cargar();
      },
      error: (e: HttpErrorResponse) => {
        this.ocupado.set(false);
        this.error.set(interpretarError(e));
      },
    });
  }

  protected etiquetaSegmento(segmento: Segmento): string {
    return this.segmentos.find((s) => s.valor === segmento)?.etiqueta ?? segmento;
  }

  protected precio(valor: number | string): string {
    return `Bs ${Number(valor).toFixed(2)}`;
  }

  protected fecha(valor: string | null): string {
    return valor ? new Date(valor).toLocaleDateString('es-BO') : '—';
  }
}

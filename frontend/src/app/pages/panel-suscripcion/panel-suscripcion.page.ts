import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';
import { PagoSuscripcionOut, PlanOut, SuscripcionOut } from '../../core/saas/saas.models';
import { SaasService } from '../../core/saas/saas.service';
import { interpretarError } from '../../shared/errores';
import { PanelShell } from '../../shared/panel/panel-shell';

/**
 * Mi suscripcion (Segundo parcial, PENDIENTES 5.4 a 5.6). Cada sucursal es un tenant con su plan:
 * la administracion de la sucursal ve su plan, el uso contra los topes y paga (o cambia de plan)
 * con Stripe Checkout; al volver, `?sesion=cs_...` se verifica contra el backend. El ADMIN de la
 * plataforma ve ademas todos los tenants y registra pagos recibidos por transferencia/efectivo.
 */
@Component({
  selector: 'app-panel-suscripcion-page',
  standalone: true,
  imports: [PanelShell, FormsModule],
  templateUrl: './panel-suscripcion.page.html',
  styleUrls: ['../../shared/panel/panel-comun.css', './panel-suscripcion.page.css'],
})
export class PanelSuscripcionPage implements OnInit {
  private readonly servicio = inject(SaasService);
  private readonly auth = inject(AuthService);
  private readonly ruta = inject(ActivatedRoute);
  private readonly router = inject(Router);

  protected readonly esAdmin = this.auth.tienePermiso('sucursales.actualizar');
  protected readonly puedePagar = this.auth.tienePermiso('suscripciones.actualizar');

  protected readonly planes = signal<PlanOut[]>([]);
  protected readonly tenants = signal<SuscripcionOut[]>([]);
  protected readonly actual = signal<SuscripcionOut | null>(null);
  protected readonly pagos = signal<PagoSuscripcionOut[]>([]);
  protected readonly cargando = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);
  protected readonly ocupado = signal(false);

  protected meses = 1;
  protected metodoManual: 'TRANSFERENCIA' | 'EFECTIVO' = 'TRANSFERENCIA';

  ngOnInit(): void {
    this.servicio.planes().subscribe({ next: (planes) => this.planes.set(planes) });
    const sesion = this.ruta.snapshot.queryParamMap.get('sesion');
    if (this.ruta.snapshot.queryParamMap.get('cancelado')) {
      this.aviso.set('Cancelaste el pago: la suscripción sigue como estaba.');
    }
    if (sesion) {
      this.servicio.verificarPago(sesion).subscribe({
        next: (s) => {
          this.aviso.set(
            s.vigente
              ? `Pago aprobado: plan ${s.plan.nombre} vigente hasta el ${this.fecha(s.vence_en)}.`
              : 'Stripe todavía no confirmó el pago. Recargá en unos segundos.',
          );
          this.router.navigate([], { queryParams: {}, replaceUrl: true });
          this.cargar(s.sucursal_id);
        },
        error: (e: HttpErrorResponse) => {
          this.error.set(interpretarError(e));
          this.cargar();
        },
      });
    } else {
      this.cargar();
    }
  }

  protected cargar(sucursalId?: string): void {
    this.cargando.set(true);
    this.servicio.suscripciones().subscribe({
      next: (tenants) => {
        this.tenants.set(tenants);
        const elegido =
          tenants.find((t) => t.sucursal_id === (sucursalId ?? this.actual()?.sucursal_id)) ?? tenants[0] ?? null;
        this.elegir(elegido);
        this.cargando.set(false);
      },
      error: (e: HttpErrorResponse) => {
        this.error.set(interpretarError(e, 'No se pudo cargar la suscripción.'));
        this.cargando.set(false);
      },
    });
  }

  protected elegir(tenant: SuscripcionOut | null): void {
    this.actual.set(tenant);
    this.pagos.set([]);
    if (!tenant) return;
    this.servicio.pagos(tenant.sucursal_id).subscribe({ next: (pagos) => this.pagos.set(pagos) });
  }

  protected pagar(plan: PlanOut): void {
    const tenant = this.actual();
    if (!tenant) return;
    this.ocupado.set(true);
    this.error.set(null);
    this.servicio
      .iniciarPago({ plan_codigo: plan.codigo, meses: this.meses, sucursal_id: tenant.sucursal_id })
      .subscribe({
        next: (checkout) => (window.location.href = checkout.url_pago),
        error: (e: HttpErrorResponse) => {
          this.ocupado.set(false);
          this.error.set(interpretarError(e));
        },
      });
  }

  protected registrarManual(plan: PlanOut): void {
    const tenant = this.actual();
    if (!tenant) return;
    this.ocupado.set(true);
    this.error.set(null);
    this.servicio
      .pagoManual(tenant.sucursal_id, { plan_codigo: plan.codigo, meses: this.meses, metodo: this.metodoManual })
      .subscribe({
        next: (s) => {
          this.ocupado.set(false);
          this.aviso.set(`Pago registrado: ${s.sucursal} queda en ${s.plan.nombre} hasta el ${this.fecha(s.vence_en)}.`);
          this.cargar(s.sucursal_id);
        },
        error: (e: HttpErrorResponse) => {
          this.ocupado.set(false);
          this.error.set(interpretarError(e));
        },
      });
  }

  protected tope(valor: number | null): string {
    return valor === null ? 'sin límite' : String(valor);
  }

  protected precio(valor: number | string): string {
    return `Bs ${Number(valor).toFixed(2)}`;
  }

  protected fecha(valor: string | null): string {
    return valor ? new Date(valor).toLocaleDateString('es-BO') : '—';
  }
}

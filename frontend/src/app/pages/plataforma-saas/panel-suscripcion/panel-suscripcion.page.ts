import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';

import { AuthService } from '../../../core/acceso-y-organizacion/auth/auth.service';
import { PagoSuscripcionOut, PlanOut, SuscripcionOut } from '../../../core/plataforma-saas/saas/saas.models';
import { SaasService } from '../../../core/plataforma-saas/saas/saas.service';
import { interpretarError } from '../../../shared/errores';
import { PanelShell } from '../../../shared/panel/panel-shell';

/**
 * Mi suscripcion (CU04). La empresa es el tenant: su administracion ve el plan, el uso contra
 * los topes (sucursales, personal, cajas) y paga o cambia de plan con Stripe Checkout; al volver,
 * `?sesion=cs_...` se verifica contra el backend. Las empresas, las renovaciones manuales y la
 * configuracion de los planes son de la plataforma (pages/panel-empresas).
 */
@Component({
  selector: 'app-panel-suscripcion-page',
  standalone: true,
  imports: [PanelShell, FormsModule],
  templateUrl: './panel-suscripcion.page.html',
  styleUrls: ['../../../shared/panel/panel-comun.css', './panel-suscripcion.page.css'],
})
export class PanelSuscripcionPage implements OnInit {
  private readonly servicio = inject(SaasService);
  private readonly auth = inject(AuthService);
  private readonly ruta = inject(ActivatedRoute);
  private readonly router = inject(Router);

  protected readonly puedePagar = this.auth.tienePermiso('suscripciones.actualizar');

  protected readonly planes = signal<PlanOut[]>([]);
  protected readonly actual = signal<SuscripcionOut | null>(null);
  protected readonly pagos = signal<PagoSuscripcionOut[]>([]);
  protected readonly cargando = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);
  protected readonly ocupado = signal(false);

  protected meses = 1;

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
          this.cargar();
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

  protected cargar(): void {
    this.cargando.set(true);
    this.servicio.miSuscripcion().subscribe({
      next: (s) => {
        this.actual.set(s);
        this.cargando.set(false);
        // el plan o la vigencia pudieron cambiar: que el menu (funciones del plan) se entere
        this.auth.refrescarSesion().subscribe({ error: () => undefined });
      },
      error: (e: HttpErrorResponse) => {
        this.error.set(interpretarError(e, 'No se pudo cargar la suscripción.'));
        this.cargando.set(false);
      },
    });
    this.servicio.pagos().subscribe({ next: (pagos) => this.pagos.set(pagos) });
  }

  protected pagar(plan: PlanOut): void {
    this.ocupado.set(true);
    this.error.set(null);
    this.servicio.iniciarPago({ plan_codigo: plan.codigo, meses: this.meses }).subscribe({
      next: (checkout) => (window.location.href = checkout.url_pago),
      error: (e: HttpErrorResponse) => {
        this.ocupado.set(false);
        this.error.set(interpretarError(e));
      },
    });
  }

  protected tope(valor: number | null): string {
    return valor === null ? 'sin límite' : String(valor);
  }

  protected excede(uso: number, tope: number | null): boolean {
    return tope !== null && uso >= tope;
  }

  protected precio(valor: number | string): string {
    return `Bs ${Number(valor).toFixed(2)}`;
  }

  protected fecha(valor: string | null): string {
    return valor ? new Date(valor).toLocaleDateString('es-BO') : '—';
  }
}

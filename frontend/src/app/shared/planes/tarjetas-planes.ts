import { Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';

import { PlanOut } from '../../core/plataforma-saas/saas/saas.models';
import { SaasService } from '../../core/plataforma-saas/saas/saas.service';

interface Prestacion {
  texto: string;
  incluida: boolean;
}

/**
 * Tarjetas de planes del SaaS (CU01 por autoregistro). Las usan /planes y la portada: los precios
 * y los topes salen de GET /saas/planes, asi que lo que configura la plataforma (CU03) es lo que
 * se muestra aca.
 */
@Component({
  selector: 'app-tarjetas-planes',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './tarjetas-planes.html',
  styleUrl: './tarjetas-planes.css',
})
export class TarjetasPlanes implements OnInit {
  private readonly servicio = inject(SaasService);

  protected readonly planes = signal<PlanOut[]>([]);
  protected readonly cargando = signal(true);
  protected readonly error = signal<string | null>(null);

  ngOnInit(): void {
    this.servicio.planes().subscribe({
      next: (planes) => {
        this.planes.set(planes);
        this.cargando.set(false);
      },
      error: () => {
        this.error.set('No se pudieron cargar los planes. Intentá de nuevo en unos segundos.');
        this.cargando.set(false);
      },
    });
  }

  protected esGratis(plan: PlanOut): boolean {
    return Number(plan.precio_mensual) === 0;
  }

  protected precio(valor: number | string): string {
    return Number(valor) === 0 ? 'Gratis' : `Bs ${Number(valor).toFixed(0)}`;
  }

  /** El plan mas completo se marca como recomendado. */
  protected esDestacado(plan: PlanOut): boolean {
    return plan.ia_reportes && plan.analitica_ml;
  }

  /** Los topes de cada plan: lo primero que distingue uno de otro. */
  protected topes(plan: PlanOut): Prestacion[] {
    const tope = (valor: number | null, singular: string, plural: string) =>
      valor === null
        ? `${plural.charAt(0).toUpperCase()}${plural.slice(1)} sin límite`
        : `Hasta ${valor} ${valor === 1 ? singular : plural}`;
    return [
      { texto: tope(plan.max_sucursales, 'sucursal', 'sucursales'), incluida: true },
      { texto: tope(plan.max_empleados, 'persona de personal', 'personas de personal'), incluida: true },
      { texto: tope(plan.max_cajas, 'caja', 'cajas'), incluida: true },
    ];
  }

  private funciones(plan: PlanOut): Prestacion[] {
    return [
      { texto: 'Reportes e indicadores', incluida: plan.reportes },
      { texto: 'Venta sin conexión', incluida: plan.operacion_offline },
      { texto: 'Perfiles de clientas', incluida: plan.perfiles_clientes },
      { texto: 'Traspasos entre sucursales', incluida: plan.traspasos },
      { texto: 'Reportes con IA', incluida: plan.ia_reportes },
      { texto: 'Analítica predictiva (ML)', incluida: plan.analitica_ml },
    ];
  }

  /** El primer plan lista todo (con lo que no trae atenuado); los siguientes solo lo que suman
   * sobre el anterior ("Todo lo del Basico y además"), asi se ve de un vistazo que cambia. */
  protected funcionesDe(plan: PlanOut, indice: number): Prestacion[] {
    const propias = this.funciones(plan);
    if (indice === 0) return propias;
    const previas = this.funciones(this.planes()[indice - 1]);
    return propias.filter((f, i) => f.incluida && !previas[i].incluida);
  }

  protected anterior(indice: number): string | null {
    return indice === 0 ? null : this.planes()[indice - 1].nombre;
  }
}

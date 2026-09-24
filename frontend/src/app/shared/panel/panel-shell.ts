import { Component, OnInit, computed, inject, input } from '@angular/core';
import { Router, RouterLink, RouterLinkActive } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';
import { PERMISO_ATENDER_RESERVAS, PERMISO_CAJA } from '../../core/auth/auth.guard';
import { CampanaNotificaciones } from '../notificaciones/campana-notificaciones';

interface EntradaNav {
  ruta: string;
  etiqueta: string;
  visible: (auth: AuthService) => boolean;
}

/**
 * Secciones del panel de gestion (CU09 a CU13), en el orden en que se muestran en la
 * navegacion. `primeraSeccionPanel` reusa esta misma lista para saber a donde mandar a un
 * usuario que entra a /panel sin una seccion puntual.
 */
const ENTRADAS_PANEL: EntradaNav[] = [
  {
    ruta: '/panel/catalogo',
    etiqueta: 'Catálogo',
    visible: (auth) => auth.tienePermiso('catalogo.crear', 'catalogo.actualizar', 'catalogo.eliminar'),
  },
  {
    ruta: '/panel/recepciones',
    etiqueta: 'Recepciones',
    visible: (auth) => auth.tienePermiso('recepciones.leer', 'recepciones.crear'),
  },
  {
    ruta: '/panel/inventario',
    etiqueta: 'Inventario',
    visible: (auth) => auth.tienePermiso('inventario.leer', 'inventario.actualizar'),
  },
  {
    ruta: '/panel/traspasos',
    etiqueta: 'Traspasos',
    visible: (auth) =>
      auth.tienePermiso('traspasos.leer', 'traspasos.crear', 'traspasos.actualizar', 'traspasos.eliminar'),
  },
  {
    ruta: '/panel/devoluciones',
    etiqueta: 'Devoluciones',
    visible: (auth) =>
      auth.tienePermiso('devoluciones.leer', 'devoluciones.crear', 'devoluciones.actualizar'),
  },
  {
    ruta: '/panel/proveedores',
    etiqueta: 'Proveedores',
    visible: (auth) =>
      auth.tienePermiso(
        'proveedores.leer',
        'proveedores.crear',
        'proveedores.actualizar',
        'proveedores.eliminar',
      ),
  },
  {
    ruta: '/panel/sucursales',
    etiqueta: 'Sucursales',
    visible: (auth) =>
      auth.tienePermiso(
        'sucursales.leer',
        'sucursales.crear',
        'sucursales.actualizar',
        'sucursales.eliminar',
      ),
  },
  {
    ruta: '/panel/usuarios',
    etiqueta: 'Usuarios y roles',
    visible: (auth) =>
      auth.tienePermiso(
        'usuarios.leer',
        'usuarios.crear',
        'usuarios.actualizar',
        'usuarios.eliminar',
        'roles.leer',
      ),
  },
  {
    ruta: '/panel/reportes',
    etiqueta: 'Reportes',
    visible: (auth) => auth.tienePermiso('reportes.leer'),
  },
  {
    ruta: '/panel/auditoria',
    etiqueta: 'Auditoría',
    visible: (auth) => auth.tienePermiso('auditoria.leer'),
  },
  { ruta: '/caja', etiqueta: 'Caja', visible: (auth) => auth.tienePermiso(PERMISO_CAJA) },
  {
    ruta: '/atender-reservas',
    etiqueta: 'Reservas',
    visible: (auth) => auth.tienePermiso(PERMISO_ATENDER_RESERVAS),
  },
];

/** A donde mandar a quien entra a /panel: su primera seccion habilitada, o la tienda si no tiene ninguna. */
export function primeraSeccionPanel(auth: AuthService): string {
  return ENTRADAS_PANEL.find((entrada) => entrada.visible(auth))?.ruta ?? '/tienda';
}

/**
 * Cabecera y navegacion comunes del panel de gestion (CU09 a CU13). Los enlaces se arman con
 * los permisos del rol: un CAJERO solo ve Caja, un ADMIN los ve todos.
 */
@Component({
  selector: 'app-panel-shell',
  standalone: true,
  imports: [CampanaNotificaciones, RouterLink, RouterLinkActive],
  templateUrl: './panel-shell.html',
  styleUrl: './panel-shell.css',
})
export class PanelShell implements OnInit {
  readonly titulo = input.required<string>();
  readonly bajada = input<string>('');

  protected readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  protected readonly navegacion = computed(() =>
    ENTRADAS_PANEL.filter((entrada) => entrada.visible(this.auth)),
  );

  protected readonly inicio = computed(() => primeraSeccionPanel(this.auth));

  ngOnInit(): void {
    // si el administrador cambio los permisos del rol, esta es la oportunidad de enterarse
    this.auth.refrescarSesion().subscribe({ error: () => undefined });
  }

  protected cerrarSesion(): void {
    this.auth.cerrarSesion();
    this.router.navigateByUrl('/login');
  }
}

import { Component, computed, inject, input } from '@angular/core';
import { Router, RouterLink, RouterLinkActive } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';

interface EntradaNav {
  ruta: string;
  etiqueta: string;
  visible: () => boolean;
}

/**
 * Cabecera y navegacion comunes del panel de gestion (CU09 a CU13). Los enlaces se arman con
 * los permisos del rol: un ALMACEN solo ve Recepciones, un ADMIN los ve todos.
 */
@Component({
  selector: 'app-panel-shell',
  standalone: true,
  imports: [RouterLink, RouterLinkActive],
  templateUrl: './panel-shell.html',
  styleUrl: './panel-shell.css',
})
export class PanelShell {
  readonly titulo = input.required<string>();
  readonly bajada = input<string>('');

  protected readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  private readonly entradas: EntradaNav[] = [
    { ruta: '/panel', etiqueta: 'Panel', visible: () => true },
    {
      ruta: '/panel/catalogo',
      etiqueta: 'Catálogo',
      visible: () =>
        this.auth.tienePermiso('catalogo.crear', 'catalogo.actualizar', 'catalogo.eliminar'),
    },
    {
      ruta: '/panel/recepciones',
      etiqueta: 'Recepciones',
      visible: () => this.auth.tienePermiso('recepciones.leer', 'recepciones.crear'),
    },
    {
      ruta: '/panel/proveedores',
      etiqueta: 'Proveedores',
      visible: () =>
        this.auth.tienePermiso(
          'proveedores.leer',
          'proveedores.crear',
          'proveedores.actualizar',
          'proveedores.eliminar',
        ),
    },
    {
      ruta: '/panel/sucursales',
      etiqueta: 'Sucursales',
      visible: () =>
        this.auth.tienePermiso(
          'sucursales.leer',
          'sucursales.crear',
          'sucursales.actualizar',
          'sucursales.eliminar',
        ),
    },
    {
      ruta: '/panel/usuarios',
      etiqueta: 'Usuarios y roles',
      visible: () =>
        this.auth.tienePermiso(
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
      visible: () => this.auth.tienePermiso('reportes.leer'),
    },
    {
      ruta: '/panel/auditoria',
      etiqueta: 'Auditoría',
      visible: () => this.auth.tienePermiso('auditoria.leer'),
    },
    {
      ruta: '/panel/envios',
      etiqueta: 'Envíos',
      visible: () => this.auth.tienePermiso('envios.leer', 'envios.actualizar'),
    },
    { ruta: '/caja', etiqueta: 'Caja', visible: () => this.auth.usuario()?.rol === 'CAJERO' },
    {
      ruta: '/atender-reservas',
      etiqueta: 'Reservas',
      visible: () => this.auth.usuario()?.rol === 'ENCARGADO',
    },
  ];

  protected readonly navegacion = computed(() =>
    this.entradas.filter((entrada) => entrada.visible()),
  );

  protected cerrarSesion(): void {
    this.auth.cerrarSesion();
    this.router.navigateByUrl('/login');
  }
}

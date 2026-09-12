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
      visible: () => this.auth.tienePermiso('catalogo.gestionar'),
    },
    {
      ruta: '/panel/recepciones',
      etiqueta: 'Recepciones',
      visible: () => this.auth.tienePermiso('recepciones.ver', 'recepciones.registrar'),
    },
    {
      ruta: '/panel/proveedores',
      etiqueta: 'Proveedores',
      visible: () => this.auth.tienePermiso('proveedores.ver', 'proveedores.gestionar'),
    },
    {
      ruta: '/panel/sucursales',
      etiqueta: 'Sucursales',
      visible: () => this.auth.tienePermiso('sucursales.ver', 'sucursales.gestionar'),
    },
    {
      ruta: '/panel/usuarios',
      etiqueta: 'Usuarios y roles',
      visible: () => this.auth.tienePermiso('usuarios.ver', 'usuarios.gestionar', 'roles.ver'),
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

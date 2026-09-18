import { Component, OnInit, computed, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';
import { PanelShell } from '../../shared/panel/panel-shell';

interface Acceso {
  ruta: string;
  titulo: string;
  descripcion: string;
  caso: string;
  permisos: string[];
}

const ACCESOS: Acceso[] = [
  {
    ruta: '/panel/catalogo',
    titulo: 'Catálogo',
    descripcion: 'Alta y baja de prendas, variantes por talla y color, imágenes y categorías.',
    caso: 'CU10',
    permisos: ['catalogo.crear', 'catalogo.actualizar', 'catalogo.eliminar'],
  },
  {
    ruta: '/panel/recepciones',
    titulo: 'Recepciones',
    descripcion: 'Cargá la mercadería que llega del proveedor y confirmala para que entre al stock.',
    caso: 'CU09',
    permisos: ['recepciones.leer', 'recepciones.crear', 'recepciones.actualizar', 'recepciones.eliminar'],
  },
  {
    ruta: '/panel/proveedores',
    titulo: 'Proveedores',
    descripcion: 'Padrón de proveedores con NIT y datos de contacto.',
    caso: 'CU11',
    permisos: ['proveedores.leer', 'proveedores.crear', 'proveedores.actualizar', 'proveedores.eliminar'],
  },
  {
    ruta: '/panel/sucursales',
    titulo: 'Sucursales',
    descripcion: 'Tiendas de la cadena, horarios, vestidores y cajas.',
    caso: 'CU12',
    permisos: ['sucursales.leer', 'sucursales.crear', 'sucursales.actualizar', 'sucursales.eliminar'],
  },
  {
    ruta: '/panel/usuarios',
    titulo: 'Usuarios y roles',
    descripcion: 'Personal de la cadena y qué puede hacer cada rol.',
    caso: 'CU13',
    permisos: ['usuarios.leer', 'usuarios.crear', 'usuarios.actualizar', 'usuarios.eliminar', 'roles.leer'],
  },
  {
    ruta: '/panel/reportes',
    titulo: 'Reportes',
    descripcion: 'Indicadores de ventas, reservas e inventario, dinámicos y con foto actual.',
    caso: 'CU15',
    permisos: ['reportes.leer'],
  },
  {
    ruta: '/panel/auditoria',
    titulo: 'Auditoría',
    descripcion: 'Quién hizo qué y cuándo: bitácora de altas, bajas y modificaciones del sistema.',
    caso: 'CU19',
    permisos: ['auditoria.leer'],
  },
];

@Component({
  selector: 'app-panel-page',
  standalone: true,
  imports: [PanelShell, RouterLink],
  templateUrl: './panel.page.html',
  styleUrls: ['../../shared/panel/panel-comun.css', './panel.page.css'],
})
export class PanelPage implements OnInit {
  protected readonly auth = inject(AuthService);

  protected readonly accesos = computed(() =>
    ACCESOS.filter((acceso) => this.auth.tienePermiso(...acceso.permisos)),
  );

  ngOnInit(): void {
    // si el administrador cambio los permisos del rol, esta es la oportunidad de enterarse
    this.auth.refrescarSesion().subscribe({ error: () => undefined });
  }
}

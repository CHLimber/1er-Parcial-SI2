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
    permisos: ['catalogo.gestionar'],
  },
  {
    ruta: '/panel/recepciones',
    titulo: 'Recepciones',
    descripcion: 'Cargá la mercadería que llega del proveedor y confirmala para que entre al stock.',
    caso: 'CU09',
    permisos: ['recepciones.ver', 'recepciones.registrar'],
  },
  {
    ruta: '/panel/proveedores',
    titulo: 'Proveedores',
    descripcion: 'Padrón de proveedores con NIT y datos de contacto.',
    caso: 'CU11',
    permisos: ['proveedores.ver', 'proveedores.gestionar'],
  },
  {
    ruta: '/panel/sucursales',
    titulo: 'Sucursales',
    descripcion: 'Tiendas de la cadena, horarios, vestidores y cajas.',
    caso: 'CU12',
    permisos: ['sucursales.ver', 'sucursales.gestionar'],
  },
  {
    ruta: '/panel/usuarios',
    titulo: 'Usuarios y roles',
    descripcion: 'Personal de la cadena y qué puede hacer cada rol.',
    caso: 'CU13',
    permisos: ['usuarios.ver', 'usuarios.gestionar', 'roles.ver'],
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

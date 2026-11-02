import {
  AfterViewInit,
  Component,
  ElementRef,
  HostListener,
  OnDestroy,
  OnInit,
  computed,
  effect,
  inject,
  input,
  signal,
} from '@angular/core';
import { Router, RouterLink, RouterLinkActive } from '@angular/router';

import { AuthService } from '../../core/acceso-y-organizacion/auth/auth.service';
import { PERMISO_ATENDER_RESERVAS, PERMISO_CAJA } from '../../core/acceso-y-organizacion/auth/auth.guard';
import { CampanaNotificaciones } from '../notificaciones/campana-notificaciones';
import { Icono } from './icono';

const CLAVE_SCROLL_LATERAL = 'fashionstore.panel.lateral-scroll';

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
    // la plataforma (SUPERADMIN): empresas contratantes, planes y suscripciones de todas
    ruta: '/panel/empresas',
    etiqueta: 'Empresas',
    visible: (auth) => auth.tienePermiso('empresas.leer'),
  },
  {
    // la plataforma (SUPERADMIN): cuentas, roles y permisos de todas las empresas
    ruta: '/panel/gobierno',
    etiqueta: 'Cuentas y roles',
    visible: (auth) => auth.tienePermiso('empresas.leer'),
  },
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
    ruta: '/panel/clientes',
    etiqueta: 'Clientas',
    visible: (auth) => auth.tienePermiso('clientes.leer', 'clientes.actualizar'),
  },
  {
    ruta: '/panel/suscripcion',
    etiqueta: 'Suscripción',
    visible: (auth) =>
      auth.tienePermiso('suscripciones.leer', 'suscripciones.actualizar') && !auth.esPlataforma(),
  },
  {
    ruta: '/panel/analitica',
    etiqueta: 'Analítica ML',
    visible: (auth) => auth.tienePermiso('analitica.leer') && !auth.esPlataforma(),
  },
  {
    ruta: '/panel/sincronizacion',
    etiqueta: 'Sincronización',
    visible: (auth) => auth.tienePermiso('sincronizacion.leer', 'sincronizacion.actualizar'),
  },
  {
    ruta: '/offline',
    etiqueta: 'Vender sin conexión',
    visible: (auth) => auth.tienePermiso(PERMISO_CAJA, PERMISO_ATENDER_RESERVAS),
  },
  {
    ruta: '/panel/backups',
    etiqueta: 'Copias de seguridad',
    visible: (auth) => auth.tienePermiso('backups.leer'),
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

/**
 * Como se agrupa la navegacion lateral y con que icono. Es solo presentacion: que secciones ve
 * cada usuario lo decide `visible` (sus permisos). El orden de ENTRADAS_PANEL, en cambio, define
 * a donde cae quien entra a /panel, y por eso no coincide con el orden visual.
 */
const GRUPOS: { titulo: string; rutas: string[] }[] = [
  { titulo: 'Plataforma', rutas: ['/panel/empresas', '/panel/gobierno'] },
  { titulo: 'Operación', rutas: ['/caja', '/atender-reservas', '/offline', '/panel/devoluciones'] },
  {
    titulo: 'Catálogo e inventario',
    rutas: ['/panel/catalogo', '/panel/inventario', '/panel/recepciones', '/panel/traspasos', '/panel/proveedores'],
  },
  { titulo: 'Clientas y negocio', rutas: ['/panel/clientes', '/panel/reportes', '/panel/analitica'] },
  {
    titulo: 'Administración',
    rutas: ['/panel/sucursales', '/panel/usuarios', '/panel/suscripcion', '/panel/sincronizacion', '/panel/backups', '/panel/auditoria'],
  },
];

const ICONO_POR_RUTA: Record<string, string> = {
  '/panel/empresas': 'empresas',
  '/panel/gobierno': 'usuarios',
  '/panel/catalogo': 'catalogo',
  '/panel/recepciones': 'recepciones',
  '/panel/inventario': 'inventario',
  '/panel/traspasos': 'traspasos',
  '/panel/devoluciones': 'devoluciones',
  '/panel/proveedores': 'proveedores',
  '/panel/sucursales': 'sucursales',
  '/panel/usuarios': 'usuarios',
  '/panel/reportes': 'reportes',
  '/panel/clientes': 'clientas',
  '/panel/suscripcion': 'suscripcion',
  '/panel/analitica': 'analitica',
  '/panel/sincronizacion': 'sincronizacion',
  '/offline': 'offline',
  '/panel/backups': 'backups',
  '/panel/auditoria': 'auditoria',
  '/caja': 'caja',
  '/atender-reservas': 'reservas',
};

interface GrupoNav {
  titulo: string;
  entradas: (EntradaNav & { icono: string })[];
}

/** A donde mandar a quien entra a /panel: su primera seccion habilitada, o la tienda si no tiene ninguna. */
export function primeraSeccionPanel(auth: AuthService): string {
  return ENTRADAS_PANEL.find((entrada) => entrada.visible(auth))?.ruta ?? '/tienda';
}

/**
 * Estructura comun del panel de gestion: barra lateral con la navegacion agrupada, barra superior
 * (migas, notificaciones y menu de usuario) y la cabecera de pagina. La navegacion se arma con los
 * permisos del rol: un CAJERO solo ve Caja, un ADMIN los ve todos. En pantallas chicas la barra
 * lateral pasa a ser un cajon que se abre con el boton de menu.
 *
 * Las paginas proyectan su contenido y, opcionalmente, botones de pagina con `<div acciones>`.
 */
@Component({
  selector: 'app-panel-shell',
  standalone: true,
  imports: [CampanaNotificaciones, Icono, RouterLink, RouterLinkActive],
  templateUrl: './panel-shell.html',
  styleUrl: './panel-shell.css',
})
export class PanelShell implements OnInit, AfterViewInit, OnDestroy {
  readonly titulo = input.required<string>();
  readonly bajada = input<string>('');

  protected readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly elemento = inject<ElementRef<HTMLElement>>(ElementRef);

  protected readonly menuAbierto = signal(false);
  protected readonly usuarioAbierto = signal(false);

  protected readonly navegacion = computed<GrupoNav[]>(() => {
    const visibles = new Map(ENTRADAS_PANEL.filter((e) => e.visible(this.auth)).map((e) => [e.ruta, e]));
    return GRUPOS.map((g) => ({
      titulo: g.titulo,
      entradas: g.rutas.flatMap((ruta) => {
        const entrada = visibles.get(ruta);
        return entrada ? [{ ...entrada, icono: ICONO_POR_RUTA[ruta] ?? '' }] : [];
      }),
    })).filter((g) => g.entradas.length > 0);
  });

  protected readonly inicio = computed(() => primeraSeccionPanel(this.auth));

  protected readonly iniciales = computed(() => {
    const u = this.auth.usuario();
    return `${u?.nombre?.charAt(0) ?? ''}${u?.apellido?.charAt(0) ?? ''}`.toUpperCase() || '?';
  });

  constructor() {
    // Con el cajon abierto la pagina de atras no debe deslizarse (el scroll se iria al fondo
    // por detras del velo). La clase vive en styles.css.
    effect(() => {
      document.documentElement.classList.toggle('cajon-abierto', this.menuAbierto());
    });
  }

  ngOnInit(): void {
    // si el administrador cambio los permisos del rol, esta es la oportunidad de enterarse
    this.auth.refrescarSesion().subscribe({ error: () => undefined });
  }

  /**
   * Cada pagina del panel monta su propio shell, asi que al navegar la barra lateral se
   * vuelve a crear y su scroll vuelve a cero (el menu "salta"). Se guarda la posicion al
   * destruirse y se restaura al crearse.
   */
  ngAfterViewInit(): void {
    try {
      const guardado = Number(sessionStorage.getItem(CLAVE_SCROLL_LATERAL));
      const lateral = this.elemento.nativeElement.querySelector<HTMLElement>('.lateral');
      if (lateral && guardado > 0) {
        lateral.scrollTop = guardado;
      }
    } catch {
      // sin sessionStorage (ventana privada, datos bloqueados): se arranca desde arriba
    }
  }

  ngOnDestroy(): void {
    document.documentElement.classList.remove('cajon-abierto');
    try {
      const lateral = this.elemento.nativeElement.querySelector<HTMLElement>('.lateral');
      if (lateral) {
        sessionStorage.setItem(CLAVE_SCROLL_LATERAL, String(lateral.scrollTop));
      }
    } catch {
      // idem
    }
  }

  /** Si se agranda la ventana con el cajon abierto, el cajon deja de existir: se cierra. */
  @HostListener('window:resize')
  protected alCambiarTamanio(): void {
    if (this.menuAbierto() && window.matchMedia('(min-width: 64rem)').matches) {
      this.menuAbierto.set(false);
    }
  }

  protected alternarMenu(): void {
    this.menuAbierto.update((abierto) => !abierto);
  }

  protected cerrarMenu(): void {
    this.menuAbierto.set(false);
  }

  protected alternarUsuario(): void {
    this.usuarioAbierto.update((abierto) => !abierto);
  }

  /** El menu de usuario se cierra al hacer clic afuera o con Escape; el cajon movil tambien con Escape. */
  @HostListener('document:click', ['$event'])
  protected alHacerClic(evento: MouseEvent): void {
    if (this.usuarioAbierto() && !(evento.target as HTMLElement).closest('.usuario')) {
      this.usuarioAbierto.set(false);
    }
  }

  @HostListener('document:keydown.escape')
  protected alEscape(): void {
    this.usuarioAbierto.set(false);
    this.menuAbierto.set(false);
  }

  protected cerrarSesion(): void {
    this.auth.cerrarSesion();
    this.router.navigateByUrl('/login');
  }
}

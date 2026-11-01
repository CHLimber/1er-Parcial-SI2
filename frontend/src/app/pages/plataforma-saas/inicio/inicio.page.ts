import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';

import { AuthService } from '../../../core/acceso-y-organizacion/auth/auth.service';
import { TiendaOut } from '../../../core/plataforma-saas/saas/saas.models';
import { SaasService } from '../../../core/plataforma-saas/saas/saas.service';
import { elegirTienda } from '../../../core/nucleo/tenant/tienda';
import { TarjetasPlanes } from '../../../shared/planes/tarjetas-planes';
import { resumenPrendas, resumenUbicacion } from '../../../shared/tiendas';

interface Paso {
  titulo: string;
  texto: string;
}

interface Funcion {
  titulo: string;
  texto: string;
}

/**
 * Portada publica (`/`): lo primero que ve cualquiera que abre la plataforma. Reparte a cada
 * audiencia por su camino: la clienta entra a una tienda (login / crear cuenta) y la empresa mira
 * los planes y se registra (CU01, autoregistro). Si ya hay sesion, el boton principal pasa a ser
 * "Ir a mi cuenta".
 */
@Component({
  selector: 'app-inicio-page',
  standalone: true,
  imports: [RouterLink, TarjetasPlanes],
  templateUrl: './inicio.page.html',
  styleUrl: './inicio.page.css',
})
export class InicioPage implements OnInit {
  private readonly auth = inject(AuthService);
  private readonly saas = inject(SaasService);
  private readonly router = inject(Router);

  protected readonly tiendas = signal<TiendaOut[]>([]);
  protected readonly cargandoTiendas = signal(true);
  /** Tarjetas fantasma mientras llegan las tiendas: reservan el alto y evitan el salto. */
  protected readonly esqueleto = [1, 2, 3];
  protected readonly anio = new Date().getFullYear();

  protected readonly conSesion = this.auth.estaAutenticado;
  protected readonly nombre = computed(() => this.auth.usuario()?.nombre ?? '');
  /** Misma regla que el login: la caja entra directo a su pantalla, el resto a la tienda. */
  protected readonly destino = computed(() => {
    const u = this.auth.usuario();
    return u?.tipo === 'STAFF' && u.rol === 'CAJERO' ? '/caja' : '/tienda';
  });

  protected readonly pasos: Paso[] = [
    {
      titulo: 'Elegí tu prenda',
      texto: 'Mirá el catálogo de cada tienda, con talla y color disponibles en tiempo real por sucursal.',
    },
    {
      titulo: 'Reservala y probátela',
      texto: 'Apartala sin pagar, pasá por la sucursal y probátela en el vestidor. Si no te queda, no la llevás.',
    },
    {
      titulo: 'Llevátela o pedila a casa',
      texto: 'Pagá en la tienda o en línea con tarjeta o QR, y recibila en tu domicilio o retirala.',
    },
  ];

  protected readonly funciones: Funcion[] = [
    { titulo: 'Catálogo y variantes', texto: 'Prendas por talla y color, con fotos, categorías, temporadas y promociones.' },
    { titulo: 'Inventario por sucursal', texto: 'Stock exacto en cada local, recepciones, ajustes y traspasos entre sucursales.' },
    { titulo: 'Caja y venta presencial', texto: 'Apertura y cierre de caja, arqueo y cobro en el mostrador, incluso sin conexión.' },
    { titulo: 'Reservas en vestidor', texto: 'La clienta aparta, el encargado confirma y la prenda queda lista para probarse.' },
    { titulo: 'Ventas online', texto: 'Carrito, pago con Stripe, QR o efectivo, y entrega a domicilio con costo por distancia.' },
    { titulo: 'Reportes e inteligencia', texto: 'Indicadores, reportes con IA, recomendaciones y analítica predictiva de demanda.' },
  ];

  ngOnInit(): void {
    this.saas.tiendas().subscribe({
      next: (tiendas) => {
        this.tiendas.set(tiendas);
        this.cargandoTiendas.set(false);
      },
      error: () => this.cargandoTiendas.set(false),
    });
  }

  /** La clienta elige a que tienda entra: se recuerda y sigue al login (o a la tienda si ya entro). */
  protected readonly resumenUbicacion = resumenUbicacion;
  protected readonly resumenPrendas = resumenPrendas;

  protected entrarATienda(tienda: TiendaOut): void {
    elegirTienda(tienda.slug);
    void this.router.navigateByUrl(this.conSesion() ? this.destino() : '/login');
  }
}

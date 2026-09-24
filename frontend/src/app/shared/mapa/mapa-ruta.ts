import {
  AfterViewInit,
  Component,
  ElementRef,
  NgZone,
  OnDestroy,
  effect,
  inject,
  input,
  viewChild,
} from '@angular/core';
import * as L from 'leaflet';

import { TILES_ATRIBUCION, TILES_URL } from './mapa-punto';

type Punto = [number, number];

/**
 * Ruta aproximada del delivery (CU20), de solo lectura: la sucursal, el domicilio y la linea
 * por donde iria el servicio de delivery externo. La usa el carrito cuando la clienta elige
 * envio a domicilio. Mismos tiles y mismo criterio de alto/ResizeObserver que `MapaPunto`.
 */
@Component({
  selector: 'app-mapa-ruta',
  standalone: true,
  template: '<div class="lienzo" #lienzo></div>',
  styles: [
    `
      :host {
        display: block;
        position: relative;
        height: 100%;
        min-height: 12rem;
      }

      .lienzo {
        position: absolute;
        inset: 0;
        border-radius: var(--radius);
        overflow: hidden;
        border: 1px solid var(--paper-line);
        z-index: 0;
      }

      :host ::ng-deep .pin-ruta {
        display: grid;
        place-items: center;
      }

      :host ::ng-deep .pin-ruta span {
        width: 16px;
        height: 16px;
        border-radius: 50%;
        border: 3px solid var(--white);
        box-shadow: 0 2px 6px rgb(46 37 48 / 40%);
      }

      :host ::ng-deep .pin-ruta--origen span {
        background: var(--ink);
      }

      :host ::ng-deep .pin-ruta--destino span {
        background: var(--flame);
      }

      :host ::ng-deep .leaflet-container {
        font-family: var(--font-body);
        background: var(--paper);
      }
    `,
  ],
})
export class MapaRuta implements AfterViewInit, OnDestroy {
  private readonly lienzo = viewChild.required<ElementRef<HTMLDivElement>>('lienzo');
  private readonly zona = inject(NgZone);

  readonly origen = input.required<Punto>();
  readonly destino = input.required<Punto>();
  readonly ruta = input<Punto[]>([]);
  /** true cuando ningun servicio de rutas respondio y la linea es recta: se dibuja punteada. */
  readonly aproximada = input(false);

  private mapa?: L.Map;
  private capa?: L.LayerGroup;
  private observador?: ResizeObserver;

  constructor() {
    // se vuelve a dibujar cuando cambia la direccion o la sucursal (nueva cotizacion)
    effect(() => {
      const origen = this.origen();
      const destino = this.destino();
      const ruta = this.ruta();
      const aproximada = this.aproximada();
      if (this.mapa) this.dibujar(origen, destino, ruta, aproximada);
    });
  }

  ngAfterViewInit(): void {
    this.zona.runOutsideAngular(() => {
      this.mapa = L.map(this.lienzo().nativeElement, {
        zoomControl: true,
        attributionControl: true,
        fadeAnimation: false,
        // es para mirar: que la rueda del mouse no secuestre el scroll de la pagina
        scrollWheelZoom: false,
      });

      L.tileLayer(TILES_URL, {
        maxZoom: 20,
        attribution: TILES_ATRIBUCION,
        updateWhenZooming: false,
      }).addTo(this.mapa);

      this.dibujar(this.origen(), this.destino(), this.ruta(), this.aproximada());

      this.observador = new ResizeObserver(() => this.mapa?.invalidateSize());
      this.observador.observe(this.lienzo().nativeElement);
    });
  }

  ngOnDestroy(): void {
    this.observador?.disconnect();
    this.mapa?.remove();
  }

  private dibujar(origen: Punto, destino: Punto, ruta: Punto[], aproximada: boolean): void {
    if (!this.mapa) return;

    this.capa?.remove();
    const trazo = ruta.length >= 2 ? ruta : [origen, destino];
    const linea = L.polyline(trazo, {
      color: getComputedStyle(document.documentElement).getPropertyValue('--flame').trim() || '#c1516b',
      weight: 5,
      opacity: 0.85,
      dashArray: aproximada ? '8 8' : undefined,
    });

    this.capa = L.layerGroup([
      linea,
      L.marker(origen, { icon: this.pin('origen'), title: 'Sucursal' }),
      L.marker(destino, { icon: this.pin('destino'), title: 'Tu dirección' }),
    ]).addTo(this.mapa);

    this.mapa.fitBounds(linea.getBounds(), { padding: [28, 28], maxZoom: 16 });
  }

  private pin(tipo: 'origen' | 'destino'): L.DivIcon {
    return L.divIcon({
      className: `pin-ruta pin-ruta--${tipo}`,
      html: '<span></span>',
      iconSize: [22, 22],
      iconAnchor: [11, 11],
    });
  }
}

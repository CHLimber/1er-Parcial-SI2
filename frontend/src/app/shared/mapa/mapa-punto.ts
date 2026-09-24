import {
  AfterViewInit,
  Component,
  ElementRef,
  NgZone,
  OnDestroy,
  effect,
  inject,
  input,
  output,
  viewChild,
} from '@angular/core';
import * as L from 'leaflet';

/**
 * Proveedor de los tiles del mapa.
 *
 * CARTO ("Voyager", el estilo con mas color y nombres de calle bien legibles) y no el servidor
 * comunitario `tile.openstreetmap.org`: ese ultimo sirve desde Europa, tiene poca presencia en
 * Sudamerica y ademas limita el uso, asi que desde Bolivia cada tile pagaba un viaje larguisimo
 * y el mapa aparecia de a pedazos grises. CARTO reparte por CDN global (con POP en la region),
 * es gratis para este volumen y el dato sigue siendo OpenStreetMap -- el mismo sobre el que
 * openrouteservice calcula la ruta del envio.
 *
 * Sin el `{s}` de los subdominios a proposito: CARTO responde por HTTP/2, que multiplexa todos
 * los tiles sobre una sola conexion. Repartir entre `a.` `b.` `c.` `d.` solo agregaria tres
 * handshakes TLS mas -- ese truco era para HTTP/1.1, donde el navegador abria 6 conexiones por
 * host como maximo.
 *
 * Para cambiar de proveedor alcanza con tocar estas dos constantes (y el `preconnect` de
 * `index.html`, que adelanta el DNS + TLS del host). Alternativas sin API key:
 *   - OSM comunitario: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png' (z<=19)
 *   - CARTO Positron (gris claro, mas sobrio): .../rastertiles/light_all/{z}/{x}/{y}.png
 *   - Esri World Street Map:
 *     'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}'
 */
export const TILES_URL = 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
export const TILES_ATRIBUCION = '&copy; OpenStreetMap &copy; CARTO';

/**
 * Mapa de un solo punto (CU20). Lo usan la libreta de direcciones -- donde la clienta arrastra
 * el pin hasta su casa -- y el panel de despacho, donde el mismo mapa se muestra bloqueado para
 * ver a donde va el paquete.
 *
 * El marcador es un divIcon con CSS propio y no el icono por defecto de Leaflet a proposito:
 * ese icono se sirve como PNG desde node_modules/leaflet/dist/images y el builder de Angular no
 * lo copia a los assets, asi que se veria roto. Dibujado en CSS ademas entra en la paleta.
 *
 * El alto lo fija el padre (`.mapa { height: ... }`); el lienzo se posiciona absoluto sobre el
 * host para llenarlo exacto y no desbordarlo cuando ese alto es chico.
 */
@Component({
  selector: 'app-mapa-punto',
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

      :host ::ng-deep .pin-fs {
        width: 26px;
        height: 26px;
        display: grid;
        place-items: center;
      }

      :host ::ng-deep .pin-fs span {
        width: 18px;
        height: 18px;
        border-radius: 50% 50% 50% 0;
        transform: rotate(-45deg);
        background: var(--flame);
        border: 2px solid var(--white);
        box-shadow: 0 2px 6px rgb(46 37 48 / 40%);
      }

      :host ::ng-deep .leaflet-container {
        font-family: var(--font-body);
        background: var(--paper);
      }
    `,
  ],
})
export class MapaPunto implements AfterViewInit, OnDestroy {
  private readonly lienzo = viewChild.required<ElementRef<HTMLDivElement>>('lienzo');
  private readonly zona = inject(NgZone);

  readonly latitud = input<number | null>(null);
  readonly longitud = input<number | null>(null);
  readonly zoom = input(15);
  /** false en el panel de despacho: ahi el mapa es para mirar, no para mover el pin. */
  readonly editable = input(true);
  /** Coordenadas nuevas cuando la clienta arrastra el pin o toca el mapa. */
  readonly puntoCambiado = output<{ latitud: number; longitud: number }>();

  private mapa?: L.Map;
  private marcador?: L.Marker;
  private observador?: ResizeObserver;
  /**
   * El punto que acabamos de emitir nosotros vuelve como input; sin esta marca el effect
   * re-centraria el mapa en cada click o dragend y el mapa "saltaria" bajo el cursor.
   */
  private puntoPropio: string | null = null;

  constructor() {
    // el pin sigue a las coordenadas cuando cambian desde afuera (buscador de direcciones,
    // "usar mi ubicacion", o al abrir otra direccion de la libreta)
    effect(() => {
      const lat = this.latitud();
      const lon = this.longitud();
      if (!this.mapa) return;

      if (lat === null || lon === null) {
        // se paso de "editar" a "nueva direccion" sin cerrar el formulario: el pin de la
        // direccion anterior no puede quedar puesto, todavia no hay punto elegido
        this.borrarPin();
        return;
      }

      this.ubicar(lat, lon);

      if (this.puntoPropio === `${lat},${lon}`) {
        this.puntoPropio = null;
        return;
      }

      // el punto vino de afuera: ademas de mover el pin hay que ir a verlo, y acercar si el
      // mapa seguia en la vista general de la ciudad (si no, la direccion buscada queda como
      // un punto perdido en el departamento y parece que el buscador no encontro nada)
      this.mapa.setView([lat, lon], Math.max(this.mapa.getZoom(), this.zoom()));
    });
  }

  ngAfterViewInit(): void {
    // Santa Cruz de la Sierra como vista inicial cuando todavia no hay punto elegido
    const centro: L.LatLngExpression = [this.latitud() ?? -17.7833, this.longitud() ?? -63.1821];

    // Leaflet escucha mousemove/zoom/drag: adentro de la zona de Angular cada uno dispara
    // change detection de toda la pagina y el mapa se arrastra a tirones
    this.zona.runOutsideAngular(() => {
      this.mapa = L.map(this.lienzo().nativeElement, {
        center: centro,
        zoom: this.latitud() === null ? 12 : this.zoom(),
        zoomControl: true,
        attributionControl: true,
        // el tile aparece apenas llega en vez de entrar con un fundido de 200 ms: con una
        // conexion lenta ese fundido encima de la espera hace que el mapa se sienta mas pesado
        fadeAnimation: false,
      });

      L.tileLayer(TILES_URL, {
        maxZoom: 20,
        attribution: TILES_ATRIBUCION,
        // no volver a pedir tiles en cada cuadro de la animacion de zoom, solo al terminar
        updateWhenZooming: false,
      }).addTo(this.mapa);

      if (this.latitud() !== null && this.longitud() !== null) {
        this.ubicar(this.latitud()!, this.longitud()!);
      }

      if (this.editable()) {
        this.mapa.on('click', (evento: L.LeafletMouseEvent) => {
          this.ubicar(evento.latlng.lat, evento.latlng.lng);
          this.avisar(evento.latlng.lat, evento.latlng.lng);
        });
      }

      // El contenedor puede medir 0 o tener otro tamanio del final cuando Leaflet se inicializa:
      // el formulario recien se esta pintando, las fuentes de Google todavia no cargaron y el
      // ancho cambia despues, y las sugerencias del buscador empujan el mapa hacia abajo. Un
      // invalidateSize() unico en el arranque no alcanza -- si el tamanio cambia despues quedan
      // tiles grises y los clicks caen desplazados. El observer lo recalcula siempre.
      this.observador = new ResizeObserver(() => this.mapa?.invalidateSize());
      this.observador.observe(this.lienzo().nativeElement);
    });
  }

  ngOnDestroy(): void {
    this.observador?.disconnect();
    this.mapa?.remove();
  }

  private ubicar(latitud: number, longitud: number): void {
    if (!this.mapa) return;

    if (!this.marcador) {
      this.marcador = L.marker([latitud, longitud], {
        draggable: this.editable(),
        icon: L.divIcon({
          className: 'pin-fs',
          html: '<span></span>',
          iconSize: [26, 26],
          iconAnchor: [13, 24],
        }),
      }).addTo(this.mapa);

      this.marcador.on('dragend', () => {
        const punto = this.marcador!.getLatLng();
        this.avisar(punto.lat, punto.lng);
      });
      return;
    }

    this.marcador.setLatLng([latitud, longitud]);
  }

  private borrarPin(): void {
    if (!this.marcador) return;
    this.marcador.remove();
    this.marcador = undefined;
  }

  private avisar(latitud: number, longitud: number): void {
    const lat = Number(latitud.toFixed(7));
    const lon = Number(longitud.toFixed(7));
    this.puntoPropio = `${lat},${lon}`;
    // el mapa corre fuera de la zona: el aviso tiene que volver a entrar para que Angular
    // repinte las coordenadas y habilite el boton de guardar
    this.zona.run(() => this.puntoCambiado.emit({ latitud: lat, longitud: lon }));
  }
}

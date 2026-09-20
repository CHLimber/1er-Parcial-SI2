import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';

import {
  CIUDADES,
  CiudadBO,
  DireccionOut,
  SugerenciaDireccionOut,
} from '../../core/direcciones/direcciones.models';
import { DireccionesService } from '../../core/direcciones/direcciones.service';
import { interpretarError } from '../../shared/errores';
import { MapaPunto } from '../../shared/mapa/mapa-punto';

/**
 * CU20 - libreta de direcciones de la clienta, la puerta de entrada al delivery: sin una
 * direccion con pin en el mapa el checkout no puede cotizar el envio.
 *
 * El pin se puede poner de tres formas: buscando la direccion (geocodificador de
 * openrouteservice), tocando el mapa, o con "usar mi ubicacion" (GPS del navegador). Las tres
 * terminan en el mismo par lat/long, que es lo unico que la API necesita.
 */
@Component({
  selector: 'app-mis-direcciones-page',
  standalone: true,
  imports: [FormsModule, RouterLink, MapaPunto],
  templateUrl: './mis-direcciones.page.html',
  styleUrls: ['./mis-direcciones.page.css', '../../shared/responsive.css'],
})
export class MisDireccionesPage implements OnInit {
  private readonly direccionesService = inject(DireccionesService);

  protected readonly ciudades = CIUDADES;

  protected readonly direcciones = signal<DireccionOut[]>([]);
  protected readonly cargando = signal(true);
  protected readonly guardando = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);

  protected readonly formularioAbierto = signal(false);
  protected readonly editandoId = signal<string | null>(null);

  protected readonly sugerencias = signal<SugerenciaDireccionOut[]>([]);
  protected readonly buscando = signal(false);
  protected readonly geocodificadorDisponible = signal(true);

  // el mapa lee estas dos como signals para mover el pin cuando cambian
  protected readonly latitud = signal<number | null>(null);
  protected readonly longitud = signal<number | null>(null);

  protected alias = '';
  protected ciudad: CiudadBO = 'SANTA_CRUZ';
  protected direccion = '';
  protected referencia = '';
  protected esPrincipal = false;
  protected textoBusqueda = '';

  ngOnInit(): void {
    this.cargar();
  }

  private cargar(): void {
    this.cargando.set(true);
    this.direccionesService.listar().subscribe({
      next: (direcciones) => {
        this.direcciones.set(direcciones);
        this.cargando.set(false);
      },
      error: (error: HttpErrorResponse) => {
        this.error.set(interpretarError(error, 'No se pudieron cargar tus direcciones.'));
        this.cargando.set(false);
      },
    });
  }

  protected nueva(): void {
    this.editandoId.set(null);
    this.alias = '';
    this.ciudad = 'SANTA_CRUZ';
    this.direccion = '';
    this.referencia = '';
    this.esPrincipal = this.direcciones().length === 0;
    this.latitud.set(null);
    this.longitud.set(null);
    this.textoBusqueda = '';
    this.sugerencias.set([]);
    this.error.set(null);
    this.formularioAbierto.set(true);
  }

  protected editar(direccion: DireccionOut): void {
    this.editandoId.set(direccion.id);
    this.alias = direccion.alias;
    this.ciudad = direccion.ciudad as CiudadBO;
    this.direccion = direccion.direccion;
    this.referencia = direccion.referencia ?? '';
    this.esPrincipal = direccion.es_principal;
    this.latitud.set(direccion.latitud);
    this.longitud.set(direccion.longitud);
    this.textoBusqueda = '';
    this.sugerencias.set([]);
    this.error.set(null);
    this.formularioAbierto.set(true);
  }

  protected cerrar(): void {
    this.formularioAbierto.set(false);
    this.editandoId.set(null);
  }

  protected buscar(): void {
    const texto = this.textoBusqueda.trim();
    if (texto.length < 3) return;

    this.buscando.set(true);
    this.direccionesService.buscar(texto).subscribe({
      next: (resultado) => {
        this.geocodificadorDisponible.set(resultado.geocodificador_disponible);
        this.sugerencias.set(resultado.resultados);
        this.buscando.set(false);
      },
      error: () => {
        this.buscando.set(false);
        this.sugerencias.set([]);
      },
    });
  }

  protected usarSugerencia(sugerencia: SugerenciaDireccionOut): void {
    this.latitud.set(sugerencia.latitud);
    this.longitud.set(sugerencia.longitud);
    if (!this.direccion.trim()) {
      this.direccion = sugerencia.etiqueta;
    }
    this.sugerencias.set([]);
  }

  protected moverPin(punto: { latitud: number; longitud: number }): void {
    this.latitud.set(punto.latitud);
    this.longitud.set(punto.longitud);
  }

  protected usarMiUbicacion(): void {
    if (!navigator.geolocation) {
      this.error.set('Tu navegador no permite ubicarte; marcá el punto en el mapa.');
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (posicion) => {
        this.latitud.set(Number(posicion.coords.latitude.toFixed(7)));
        this.longitud.set(Number(posicion.coords.longitude.toFixed(7)));
      },
      () => this.error.set('No pudimos ubicarte; marcá el punto en el mapa.'),
    );
  }

  protected guardar(): void {
    this.error.set(null);

    if (this.alias.trim().length < 2 || this.direccion.trim().length < 5) {
      this.error.set('Completá el nombre de la dirección y la calle.');
      return;
    }
    if (this.latitud() === null || this.longitud() === null) {
      this.error.set('Marcá en el mapa dónde queda: sin ese punto no podemos calcular el envío.');
      return;
    }

    const datos = {
      alias: this.alias.trim(),
      ciudad: this.ciudad,
      direccion: this.direccion.trim(),
      referencia: this.referencia.trim() || null,
      latitud: this.latitud(),
      longitud: this.longitud(),
      es_principal: this.esPrincipal,
    };

    this.guardando.set(true);
    const id = this.editandoId();
    const peticion = id
      ? this.direccionesService.actualizar(id, datos)
      : this.direccionesService.crear(datos);

    peticion.subscribe({
      next: () => {
        this.guardando.set(false);
        this.formularioAbierto.set(false);
        this.aviso.set(id ? 'Dirección actualizada.' : 'Dirección guardada.');
        this.cargar();
      },
      error: (error: HttpErrorResponse) => {
        this.guardando.set(false);
        this.error.set(interpretarError(error, 'No se pudo guardar la dirección.'));
      },
    });
  }

  protected marcarPrincipal(direccion: DireccionOut): void {
    this.direccionesService.marcarPrincipal(direccion.id).subscribe({
      next: () => {
        this.aviso.set(`"${direccion.alias}" es ahora tu dirección principal.`);
        this.cargar();
      },
      error: (error: HttpErrorResponse) => this.error.set(interpretarError(error)),
    });
  }

  protected eliminar(direccion: DireccionOut): void {
    if (!confirm(`¿Borrar la dirección "${direccion.alias}"?`)) return;

    this.direccionesService.eliminar(direccion.id).subscribe({
      next: () => {
        this.aviso.set('Dirección borrada.');
        this.cargar();
      },
      error: (error: HttpErrorResponse) =>
        this.error.set(interpretarError(error, 'No se pudo borrar la dirección.')),
    });
  }

  protected nombreCiudad(codigo: string): string {
    return this.ciudades.find((ciudad) => ciudad.valor === codigo)?.etiqueta ?? codigo;
  }
}

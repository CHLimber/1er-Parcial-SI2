import { HttpErrorResponse } from '@angular/common/http';
import { Component, ElementRef, OnInit, ViewChild, computed, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';

import { AuthService } from '../../core/auth/auth.service';
import {
  CategoriaAdminOut,
  ProductoAdminDetalleOut,
  ProductoAdminOut,
  ProductoIn,
  ReferenciasOut,
  VarianteAdminOut,
  VarianteIn,
} from '../../core/catalogo/catalogo-admin.models';
import { CatalogoAdminService } from '../../core/catalogo/catalogo-admin.service';
import { interpretarError } from '../../shared/errores';
import { PanelShell } from '../../shared/panel/panel-shell';

type Vista = 'lista' | 'formulario' | 'ficha';

/** CU10 - Gestionar Catalogo. */
@Component({
  selector: 'app-panel-catalogo-page',
  standalone: true,
  imports: [PanelShell, ReactiveFormsModule],
  templateUrl: './panel-catalogo.page.html',
  styleUrls: ['../../shared/panel/panel-comun.css', './panel-catalogo.page.css'],
})
export class PanelCatalogoPage implements OnInit {
  private readonly servicio = inject(CatalogoAdminService);
  private readonly fb = inject(FormBuilder);
  private readonly auth = inject(AuthService);

  protected readonly puedeGestionar = this.auth.tienePermiso('catalogo.gestionar');

  protected solapa: 'prendas' | 'clasificacion' = 'prendas';
  protected readonly vista = signal<Vista>('lista');

  protected readonly cargando = signal(true);
  protected readonly productos = signal<ProductoAdminOut[]>([]);
  protected readonly referencias = signal<ReferenciasOut | null>(null);
  protected readonly error = signal<string | null>(null);

  protected busqueda = '';
  protected filtroCategoria = '';
  protected filtroEstado: '' | 'true' | 'false' = '';

  protected readonly ficha = signal<ProductoAdminDetalleOut | null>(null);
  protected readonly editando = signal<ProductoAdminDetalleOut | null>(null);
  protected readonly guardando = signal(false);
  protected readonly errorFormulario = signal<string | null>(null);

  protected readonly varianteEditada = signal<VarianteAdminOut | null>(null);
  protected readonly errorVariante = signal<string | null>(null);
  protected readonly errorImagen = signal<string | null>(null);

  // --- categorias y marcas ---
  protected readonly categorias = signal<CategoriaAdminOut[]>([]);
  protected readonly categoriaEditada = signal<CategoriaAdminOut | null>(null);
  protected readonly errorCategoria = signal<string | null>(null);
  protected readonly errorMarca = signal<string | null>(null);

  protected readonly colecciones = computed(() => {
    const temporadaId = this.formProducto.controls.temporada_id.value;
    const todas = this.referencias()?.colecciones ?? [];
    return temporadaId ? todas.filter((c) => c.temporada_id === temporadaId) : todas;
  });

  protected readonly formProducto = this.fb.nonNullable.group({
    codigo: ['', [Validators.required, Validators.maxLength(40)]],
    nombre: ['', [Validators.required, Validators.maxLength(180)]],
    descripcion: [''],
    categoria_id: ['', [Validators.required]],
    marca_id: [''],
    proveedor_id: [''],
    temporada_id: [''],
    coleccion_id: [''],
    material: [''],
    genero: [''],
    precio_base: [0, [Validators.required, Validators.min(0)]],
    destacado: [false],
  });

  protected readonly formVariante = this.fb.nonNullable.group({
    talla_id: [0, [Validators.required, Validators.min(1)]],
    color_id: [0, [Validators.required, Validators.min(1)]],
    sku: ['', [Validators.required, Validators.maxLength(60)]],
    codigo_barras: [''],
    precio: [null as number | null],
    precio_oferta: [null as number | null],
  });

  protected readonly formImagen = this.fb.nonNullable.group({
    url: [''],
    uso: ['CATALOGO'],
    formato: ['JPG'],
    es_principal: [false],
    orden: [0],
  });

  @ViewChild('inputArchivoImagen') private inputArchivoImagen?: ElementRef<HTMLInputElement>;
  protected archivoImagen: File | null = null;

  protected readonly formCategoria = this.fb.nonNullable.group({
    nombre: ['', [Validators.required, Validators.maxLength(80)]],
    categoria_padre_id: [''],
    imagen_url: [''],
    orden: [0],
  });

  protected readonly formMarca = this.fb.nonNullable.group({
    nombre: ['', [Validators.required, Validators.maxLength(80)]],
    logo_url: [''],
  });

  ngOnInit(): void {
    this.cargarReferencias();
    this.cargarProductos();
  }

  private cargarReferencias(): void {
    this.servicio.referencias().subscribe({
      next: (referencias) => {
        this.referencias.set(referencias);
        this.categorias.set(referencias.categorias);
      },
      error: (e: HttpErrorResponse) => this.error.set(interpretarError(e)),
    });
  }

  // ------------------------------------------------------------------
  //  PRENDAS
  // ------------------------------------------------------------------

  protected cargarProductos(): void {
    this.cargando.set(true);
    this.error.set(null);
    const activo = this.filtroEstado === '' ? null : this.filtroEstado === 'true';
    this.servicio.listarProductos(this.busqueda || null, this.filtroCategoria || null, activo).subscribe({
      next: (productos) => {
        this.productos.set(productos);
        this.cargando.set(false);
      },
      error: (e: HttpErrorResponse) => {
        this.error.set(interpretarError(e, 'No se pudo cargar el catálogo.'));
        this.cargando.set(false);
      },
    });
  }

  protected volverALista(): void {
    this.vista.set('lista');
    this.ficha.set(null);
    this.editando.set(null);
    this.cargarProductos();
  }

  protected abrirFicha(producto: ProductoAdminOut): void {
    this.error.set(null);
    this.servicio.obtenerProducto(producto.id).subscribe({
      next: (detalle) => {
        this.ficha.set(detalle);
        this.prepararFormVariante();
        this.formImagen.reset({ url: '', uso: 'CATALOGO', formato: 'JPG', es_principal: false, orden: 0 });
        this.vista.set('ficha');
      },
      error: (e: HttpErrorResponse) => this.error.set(interpretarError(e)),
    });
  }

  protected nuevaPrenda(): void {
    this.editando.set(null);
    this.errorFormulario.set(null);
    this.formProducto.reset({
      codigo: '',
      nombre: '',
      descripcion: '',
      categoria_id: this.referencias()?.categorias[0]?.id ?? '',
      marca_id: '',
      proveedor_id: '',
      temporada_id: '',
      coleccion_id: '',
      material: '',
      genero: '',
      precio_base: 0,
      destacado: false,
    });
    this.vista.set('formulario');
  }

  protected editarPrenda(detalle: ProductoAdminDetalleOut): void {
    this.editando.set(detalle);
    this.errorFormulario.set(null);
    this.formProducto.reset({
      codigo: detalle.codigo,
      nombre: detalle.nombre,
      descripcion: detalle.descripcion ?? '',
      categoria_id: detalle.categoria_id,
      marca_id: detalle.marca_id ?? '',
      proveedor_id: detalle.proveedor_id ?? '',
      temporada_id: detalle.temporada_id ?? '',
      coleccion_id: detalle.coleccion_id ?? '',
      material: detalle.material ?? '',
      genero: detalle.genero ?? '',
      precio_base: detalle.precio_base,
      destacado: detalle.destacado,
    });
    this.vista.set('formulario');
  }

  protected guardarPrenda(): void {
    if (this.formProducto.invalid) {
      this.formProducto.markAllAsTouched();
      return;
    }

    const crudo = this.formProducto.getRawValue();
    const datos: ProductoIn = {
      codigo: crudo.codigo.trim().toUpperCase(),
      nombre: crudo.nombre.trim(),
      descripcion: crudo.descripcion.trim() || null,
      categoria_id: crudo.categoria_id,
      marca_id: crudo.marca_id || null,
      proveedor_id: crudo.proveedor_id || null,
      temporada_id: crudo.temporada_id || null,
      coleccion_id: crudo.coleccion_id || null,
      material: crudo.material.trim() || null,
      genero: crudo.genero || null,
      precio_base: Number(crudo.precio_base),
      destacado: crudo.destacado,
    };

    this.guardando.set(true);
    this.errorFormulario.set(null);

    const enEdicion = this.editando();
    const peticion = enEdicion
      ? this.servicio.actualizarProducto(enEdicion.id, datos)
      : this.servicio.crearProducto(datos);

    peticion.subscribe({
      next: (detalle) => {
        this.guardando.set(false);
        this.ficha.set(detalle);
        this.editando.set(null);
        this.prepararFormVariante();
        this.vista.set('ficha');
        this.cargarProductos();
      },
      error: (e: HttpErrorResponse) => {
        this.guardando.set(false);
        this.errorFormulario.set(interpretarError(e));
      },
    });
  }

  protected alternarEstadoPrenda(detalle: ProductoAdminDetalleOut): void {
    this.error.set(null);
    this.servicio.cambiarEstadoProducto(detalle.id, !detalle.activo).subscribe({
      next: (actualizado) => {
        this.ficha.set(actualizado);
        this.cargarProductos();
      },
      error: (e: HttpErrorResponse) => this.error.set(interpretarError(e)),
    });
  }

  // ------------------------------------------------------------------
  //  VARIANTES
  // ------------------------------------------------------------------

  private prepararFormVariante(): void {
    const referencias = this.referencias();
    this.varianteEditada.set(null);
    this.errorVariante.set(null);
    this.formVariante.reset({
      talla_id: referencias?.tallas[0]?.id ?? 0,
      color_id: referencias?.colores[0]?.id ?? 0,
      sku: '',
      codigo_barras: '',
      precio: null,
      precio_oferta: null,
    });
  }

  protected editarVariante(variante: VarianteAdminOut): void {
    this.varianteEditada.set(variante);
    this.errorVariante.set(null);
    this.formVariante.reset({
      talla_id: variante.talla_id,
      color_id: variante.color_id,
      sku: variante.sku,
      codigo_barras: variante.codigo_barras ?? '',
      precio: variante.precio,
      precio_oferta: variante.precio_oferta,
    });
  }

  protected guardarVariante(): void {
    const detalle = this.ficha();
    if (!detalle || this.formVariante.invalid) {
      this.formVariante.markAllAsTouched();
      return;
    }

    const crudo = this.formVariante.getRawValue();
    const datos: VarianteIn = {
      talla_id: Number(crudo.talla_id),
      color_id: Number(crudo.color_id),
      sku: crudo.sku.trim().toUpperCase(),
      codigo_barras: crudo.codigo_barras.trim() || null,
      precio: crudo.precio === null || crudo.precio === ('' as unknown) ? null : Number(crudo.precio),
      precio_oferta:
        crudo.precio_oferta === null || crudo.precio_oferta === ('' as unknown)
          ? null
          : Number(crudo.precio_oferta),
    };

    this.guardando.set(true);
    this.errorVariante.set(null);

    const enEdicion = this.varianteEditada();
    const peticion = enEdicion
      ? this.servicio.actualizarVariante(enEdicion.id, datos)
      : this.servicio.crearVariante(detalle.id, datos);

    peticion.subscribe({
      next: () => {
        this.guardando.set(false);
        this.refrescarFicha();
      },
      error: (e: HttpErrorResponse) => {
        this.guardando.set(false);
        this.errorVariante.set(interpretarError(e));
      },
    });
  }

  protected alternarEstadoVariante(variante: VarianteAdminOut): void {
    this.errorVariante.set(null);
    this.servicio.cambiarEstadoVariante(variante.id, !variante.activa).subscribe({
      next: () => this.refrescarFicha(),
      error: (e: HttpErrorResponse) => this.errorVariante.set(interpretarError(e)),
    });
  }

  // ------------------------------------------------------------------
  //  IMAGENES
  // ------------------------------------------------------------------

  protected seleccionarArchivoImagen(event: Event): void {
    const input = event.target as HTMLInputElement;
    this.archivoImagen = input.files?.[0] ?? null;
  }

  protected agregarImagen(): void {
    const detalle = this.ficha();
    if (!detalle) return;

    const crudo = this.formImagen.getRawValue();
    const url = crudo.url.trim();
    if (!this.archivoImagen && !url) {
      this.errorImagen.set('Elegí un archivo o pegá una URL.');
      return;
    }

    this.guardando.set(true);
    this.errorImagen.set(null);

    const peticion = this.archivoImagen
      ? this.servicio.subirImagen(detalle.id, this.archivoImagen, {
          uso: crudo.uso,
          esPrincipal: crudo.es_principal,
          orden: Number(crudo.orden),
        })
      : this.servicio.agregarImagen(detalle.id, {
          url,
          uso: crudo.uso,
          formato: crudo.formato || null,
          color_id: null,
          es_principal: crudo.es_principal,
          orden: Number(crudo.orden),
        });

    peticion.subscribe({
      next: () => {
        this.guardando.set(false);
        this.archivoImagen = null;
        if (this.inputArchivoImagen) {
          this.inputArchivoImagen.nativeElement.value = '';
        }
        this.formImagen.reset({ url: '', uso: 'CATALOGO', formato: 'JPG', es_principal: false, orden: 0 });
        this.refrescarFicha();
      },
      error: (e: HttpErrorResponse) => {
        this.guardando.set(false);
        this.errorImagen.set(interpretarError(e));
      },
    });
  }

  protected eliminarImagen(imagenId: string): void {
    this.errorImagen.set(null);
    this.servicio.eliminarImagen(imagenId).subscribe({
      next: () => this.refrescarFicha(),
      error: (e: HttpErrorResponse) => this.errorImagen.set(interpretarError(e)),
    });
  }

  private refrescarFicha(): void {
    const detalle = this.ficha();
    if (!detalle) return;
    this.servicio.obtenerProducto(detalle.id).subscribe({
      next: (actualizado) => {
        this.ficha.set(actualizado);
        this.prepararFormVariante();
      },
      error: (e: HttpErrorResponse) => this.errorVariante.set(interpretarError(e)),
    });
  }

  // ------------------------------------------------------------------
  //  CATEGORIAS Y MARCAS
  // ------------------------------------------------------------------

  protected nuevaCategoria(): void {
    this.categoriaEditada.set(null);
    this.errorCategoria.set(null);
    this.formCategoria.reset({ nombre: '', categoria_padre_id: '', imagen_url: '', orden: 0 });
  }

  protected editarCategoria(categoria: CategoriaAdminOut): void {
    this.categoriaEditada.set(categoria);
    this.errorCategoria.set(null);
    this.formCategoria.reset({
      nombre: categoria.nombre,
      categoria_padre_id: categoria.categoria_padre_id ?? '',
      imagen_url: categoria.imagen_url ?? '',
      orden: categoria.orden,
    });
  }

  protected guardarCategoria(): void {
    if (this.formCategoria.invalid) {
      this.formCategoria.markAllAsTouched();
      return;
    }

    const crudo = this.formCategoria.getRawValue();
    const datos = {
      nombre: crudo.nombre.trim(),
      categoria_padre_id: crudo.categoria_padre_id || null,
      imagen_url: crudo.imagen_url.trim() || null,
      orden: Number(crudo.orden),
    };

    this.guardando.set(true);
    this.errorCategoria.set(null);

    const enEdicion = this.categoriaEditada();
    const peticion = enEdicion
      ? this.servicio.actualizarCategoria(enEdicion.id, datos)
      : this.servicio.crearCategoria(datos);

    peticion.subscribe({
      next: () => {
        this.guardando.set(false);
        this.nuevaCategoria();
        this.recargarCategorias();
      },
      error: (e: HttpErrorResponse) => {
        this.guardando.set(false);
        this.errorCategoria.set(interpretarError(e));
      },
    });
  }

  protected alternarEstadoCategoria(categoria: CategoriaAdminOut): void {
    this.errorCategoria.set(null);
    this.servicio.cambiarEstadoCategoria(categoria.id, !categoria.activa).subscribe({
      next: () => this.recargarCategorias(),
      error: (e: HttpErrorResponse) => this.errorCategoria.set(interpretarError(e)),
    });
  }

  protected guardarMarca(): void {
    if (this.formMarca.invalid) {
      this.formMarca.markAllAsTouched();
      return;
    }

    const crudo = this.formMarca.getRawValue();
    this.guardando.set(true);
    this.errorMarca.set(null);
    this.servicio.crearMarca(crudo.nombre.trim(), crudo.logo_url.trim() || null).subscribe({
      next: () => {
        this.guardando.set(false);
        this.formMarca.reset({ nombre: '', logo_url: '' });
        this.cargarReferencias();
      },
      error: (e: HttpErrorResponse) => {
        this.guardando.set(false);
        this.errorMarca.set(interpretarError(e));
      },
    });
  }

  private recargarCategorias(): void {
    this.servicio.listarCategorias().subscribe({
      next: (categorias) => this.categorias.set(categorias),
      error: (e: HttpErrorResponse) => this.errorCategoria.set(interpretarError(e)),
    });
    this.cargarReferencias();
  }

  // ------------------------------------------------------------------

  protected precio(valor: number | null | undefined): string {
    return valor === null || valor === undefined ? '—' : `Bs ${Number(valor).toFixed(2)}`;
  }
}

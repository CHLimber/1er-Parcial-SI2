import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  CategoriaAdminOut,
  CategoriaIn,
  ImagenIn,
  ImagenOut,
  MarcaAdminOut,
  ProductoAdminDetalleOut,
  ProductoAdminOut,
  ProductoIn,
  PromocionAdminOut,
  PromocionIn,
  ReferenciasOut,
  VarianteAdminOut,
  VarianteIn,
} from './catalogo-admin.models';

/** CU10 - Gestionar Catalogo. */
@Injectable({ providedIn: 'root' })
export class CatalogoAdminService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/admin/catalogo`;

  referencias(): Observable<ReferenciasOut> {
    return this.http.get<ReferenciasOut>(`${this.base}/referencias`);
  }

  listarProductos(
    q?: string | null,
    categoriaId?: string | null,
    activo?: boolean | null,
  ): Observable<ProductoAdminOut[]> {
    let params = new HttpParams();
    if (q) params = params.set('q', q);
    if (categoriaId) params = params.set('categoria_id', categoriaId);
    if (activo !== null && activo !== undefined) params = params.set('activo', activo);
    return this.http.get<ProductoAdminOut[]>(`${this.base}/productos`, { params });
  }

  obtenerProducto(id: string): Observable<ProductoAdminDetalleOut> {
    return this.http.get<ProductoAdminDetalleOut>(`${this.base}/productos/${id}`);
  }

  crearProducto(datos: ProductoIn): Observable<ProductoAdminDetalleOut> {
    return this.http.post<ProductoAdminDetalleOut>(`${this.base}/productos`, datos);
  }

  actualizarProducto(id: string, datos: ProductoIn): Observable<ProductoAdminDetalleOut> {
    return this.http.put<ProductoAdminDetalleOut>(`${this.base}/productos/${id}`, datos);
  }

  cambiarEstadoProducto(id: string, activo: boolean): Observable<ProductoAdminDetalleOut> {
    return this.http.patch<ProductoAdminDetalleOut>(`${this.base}/productos/${id}/estado`, { activo });
  }

  crearVariante(productoId: string, datos: VarianteIn): Observable<VarianteAdminOut> {
    return this.http.post<VarianteAdminOut>(`${this.base}/productos/${productoId}/variantes`, datos);
  }

  actualizarVariante(varianteId: string, datos: VarianteIn): Observable<VarianteAdminOut> {
    return this.http.put<VarianteAdminOut>(`${this.base}/variantes/${varianteId}`, datos);
  }

  cambiarEstadoVariante(varianteId: string, activo: boolean): Observable<VarianteAdminOut> {
    return this.http.patch<VarianteAdminOut>(`${this.base}/variantes/${varianteId}/estado`, { activo });
  }

  agregarImagen(productoId: string, datos: ImagenIn): Observable<ImagenOut> {
    return this.http.post<ImagenOut>(`${this.base}/productos/${productoId}/imagenes`, datos);
  }

  subirImagen(
    productoId: string,
    archivo: File,
    opciones: { uso: string; esPrincipal: boolean; orden: number },
  ): Observable<ImagenOut> {
    const formData = new FormData();
    formData.append('archivo', archivo);
    formData.append('uso', opciones.uso);
    formData.append('es_principal', String(opciones.esPrincipal));
    formData.append('orden', String(opciones.orden));
    return this.http.post<ImagenOut>(`${this.base}/productos/${productoId}/imagenes/subir`, formData);
  }

  eliminarImagen(imagenId: string): Observable<void> {
    return this.http.delete<void>(`${this.base}/imagenes/${imagenId}`);
  }

  listarCategorias(): Observable<CategoriaAdminOut[]> {
    return this.http.get<CategoriaAdminOut[]>(`${this.base}/categorias`);
  }

  crearCategoria(datos: CategoriaIn): Observable<CategoriaAdminOut> {
    return this.http.post<CategoriaAdminOut>(`${this.base}/categorias`, datos);
  }

  actualizarCategoria(id: string, datos: CategoriaIn): Observable<CategoriaAdminOut> {
    return this.http.put<CategoriaAdminOut>(`${this.base}/categorias/${id}`, datos);
  }

  cambiarEstadoCategoria(id: string, activa: boolean): Observable<CategoriaAdminOut> {
    return this.http.patch<CategoriaAdminOut>(`${this.base}/categorias/${id}/estado`, { activa });
  }

  crearMarca(nombre: string, logoUrl: string | null): Observable<MarcaAdminOut> {
    return this.http.post<MarcaAdminOut>(`${this.base}/marcas`, { nombre, logo_url: logoUrl });
  }

  listarPromociones(activa?: boolean | null): Observable<PromocionAdminOut[]> {
    let params = new HttpParams();
    if (activa !== null && activa !== undefined) params = params.set('activa', activa);
    return this.http.get<PromocionAdminOut[]>(`${this.base}/promociones`, { params });
  }

  crearPromocion(datos: PromocionIn): Observable<PromocionAdminOut> {
    return this.http.post<PromocionAdminOut>(`${this.base}/promociones`, datos);
  }

  actualizarPromocion(id: string, datos: PromocionIn): Observable<PromocionAdminOut> {
    return this.http.put<PromocionAdminOut>(`${this.base}/promociones/${id}`, datos);
  }

  cambiarEstadoPromocion(id: string, activa: boolean): Observable<PromocionAdminOut> {
    return this.http.patch<PromocionAdminOut>(`${this.base}/promociones/${id}/estado`, { activa });
  }
}

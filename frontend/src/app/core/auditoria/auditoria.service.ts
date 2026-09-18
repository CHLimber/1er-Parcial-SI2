import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { AuditoriaPaginadoOut, FiltroAuditoria } from './auditoria.models';

@Injectable({ providedIn: 'root' })
export class AuditoriaService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/auditoria`;

  listar(filtro: FiltroAuditoria, pagina: number, tamanioPagina: number): Observable<AuditoriaPaginadoOut> {
    let params = new HttpParams().set('pagina', pagina).set('tamanio_pagina', tamanioPagina);
    if (filtro.usuario_id) params = params.set('usuario_id', filtro.usuario_id);
    if (filtro.entidad) params = params.set('entidad', filtro.entidad);
    if (filtro.entidad_id) params = params.set('entidad_id', filtro.entidad_id);
    if (filtro.accion) params = params.set('accion', filtro.accion);
    if (filtro.desde) params = params.set('desde', filtro.desde);
    if (filtro.hasta) params = params.set('hasta', filtro.hasta);
    return this.http.get<AuditoriaPaginadoOut>(this.base, { params });
  }

  entidades(): Observable<string[]> {
    return this.http.get<string[]>(`${this.base}/entidades`);
  }
}

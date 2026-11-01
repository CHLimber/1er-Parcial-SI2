import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../../environments/environment';
import { BackupOut, ProgramacionOut } from './backups.models';

/** CU30 - copias de seguridad: la general de la plataforma y la de cada empresa. */
@Injectable({ providedIn: 'root' })
export class BackupsService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/backups`;

  /** Plataforma: cuando corre la copia automatica y cual fue la ultima. */
  programacion(): Observable<ProgramacionOut> {
    return this.http.get<ProgramacionOut>(`${this.base}/programacion`);
  }

  /** Plataforma: las copias generales (automaticas y manuales). */
  generales(): Observable<BackupOut[]> {
    return this.http.get<BackupOut[]>(`${this.base}/plataforma`);
  }

  crearGeneral(): Observable<BackupOut> {
    return this.http.post<BackupOut>(`${this.base}/plataforma`, {});
  }

  /** Las de mi empresa; la plataforma ve las de todas (o las de `empresaId`). */
  deEmpresa(empresaId?: string | null): Observable<BackupOut[]> {
    let params = new HttpParams();
    if (empresaId) params = params.set('empresa_id', empresaId);
    return this.http.get<BackupOut[]>(`${this.base}/empresa`, { params });
  }

  /** La empresa omite `empresaId` (es la suya); la plataforma lo indica. */
  crearDeEmpresa(empresaId?: string | null): Observable<BackupOut> {
    return this.http.post<BackupOut>(`${this.base}/empresa`, { empresa_id: empresaId ?? null });
  }

  /** El zip llega como blob: el Bearer lo pone el authInterceptor, un <a href> no lo llevaria. */
  descargar(id: string): Observable<Blob> {
    return this.http.get(`${this.base}/${id}/descargar`, { responseType: 'blob' });
  }

  eliminar(id: string): Observable<void> {
    return this.http.delete<void>(`${this.base}/${id}`);
  }
}

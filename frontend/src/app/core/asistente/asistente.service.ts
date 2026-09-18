import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { ChatOut, MensajeChat } from './asistente.models';

@Injectable({ providedIn: 'root' })
export class AsistenteService {
  private readonly http = inject(HttpClient);

  /** El backend no persiste nada (CU18): mandamos la conversacion completa en cada request. */
  chatear(mensajes: MensajeChat[]): Observable<ChatOut> {
    return this.http.post<ChatOut>(`${environment.apiUrl}/asistente/chat`, { mensajes });
  }
}

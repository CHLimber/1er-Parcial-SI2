import { HttpErrorResponse } from '@angular/common/http';
import { Component, ElementRef, ViewChild, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';

import { AsistenteService } from '../../core/asistente/asistente.service';
import { MensajeChat } from '../../core/asistente/asistente.models';
import { ProductoOut } from '../../core/catalogo/catalogo.models';
import { interpretarError } from '../../shared/errores';
import { ProductoCard } from '../../shared/catalogo/producto-card';

interface MensajeVista extends MensajeChat {
  productos?: ProductoOut[];
}

/** CU18 - Asistir al Cliente via Chatbot. Sin persistencia: la conversacion vive solo acá,
 * se pierde si se recarga la pagina (decision conversada con el usuario). */
@Component({
  selector: 'app-asistente-page',
  standalone: true,
  imports: [FormsModule, ProductoCard, RouterLink],
  templateUrl: './asistente.page.html',
  styleUrl: './asistente.page.css',
})
export class AsistentePage {
  private readonly servicio = inject(AsistenteService);

  protected readonly mensajes = signal<MensajeVista[]>([]);
  protected readonly enviando = signal(false);
  protected readonly error = signal<string | null>(null);
  protected borrador = '';

  @ViewChild('contenedor') private contenedor?: ElementRef<HTMLDivElement>;

  protected enviar(): void {
    const texto = this.borrador.trim();
    if (!texto || this.enviando()) return;

    this.borrador = '';
    this.error.set(null);
    this.mensajes.update((lista) => [...lista, { rol: 'user', texto }]);
    this.enviando.set(true);
    this.scrollAlFinal();

    const historial: MensajeChat[] = this.mensajes().map((m) => ({ rol: m.rol, texto: m.texto }));

    this.servicio.chatear(historial).subscribe({
      next: (respuesta) => {
        this.mensajes.update((lista) => [
          ...lista,
          { rol: 'assistant', texto: respuesta.respuesta, productos: respuesta.productos_sugeridos },
        ]);
        this.enviando.set(false);
        this.scrollAlFinal();
      },
      error: (e: HttpErrorResponse) => {
        this.error.set(
          interpretarError(e, 'El asistente no está disponible ahora. Probá de nuevo en un rato.'),
        );
        this.enviando.set(false);
      },
    });
  }

  private scrollAlFinal(): void {
    setTimeout(() => {
      const el = this.contenedor?.nativeElement;
      if (el) el.scrollTop = el.scrollHeight;
    });
  }
}

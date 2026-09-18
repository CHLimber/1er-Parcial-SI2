import { Pipe, PipeTransform } from '@angular/core';
import { marked } from 'marked';

marked.setOptions({ breaks: true, gfm: true });

/**
 * Renderiza texto markdown (respuestas del asistente CU18, que llegan de la API de Claude) a
 * HTML. Angular sanitiza automaticamente cualquier valor pasado por [innerHTML] -- no hace falta
 * bypassSecurityTrustHtml, marked no es la barrera de seguridad, lo es el binding de Angular.
 */
@Pipe({ name: 'markdown', standalone: true })
export class MarkdownPipe implements PipeTransform {
  transform(texto: string | null | undefined): string {
    if (!texto) return '';
    return marked.parse(texto, { async: false });
  }
}

import { ProductoOut } from '../catalogo/catalogo.models';

export interface MensajeChat {
  rol: 'user' | 'assistant';
  texto: string;
}

export interface ChatIn {
  mensajes: MensajeChat[];
}

export interface ChatOut {
  respuesta: string;
  productos_sugeridos: ProductoOut[];
}

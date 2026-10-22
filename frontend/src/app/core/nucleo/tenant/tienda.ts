import { signal } from '@angular/core';

/**
 * Multi-tenant: que tienda (empresa) se esta mirando. Cada request a la API viaja con el header
 * X-Empresa (ver auth.interceptor.ts): para el personal es siempre su empresa (la del token, el
 * backend igual la impone); para una clienta, la tienda elegida en la vitrina o la que vino en el
 * link (?empresa=slug). Se recuerda en localStorage para que al reabrir siga en la misma tienda.
 */
const CLAVE = 'fashionstore.tienda';
export const TIENDA_POR_DEFECTO = 'fashionstore';

function inicial(): string {
  try {
    const delLink = new URLSearchParams(globalThis.location?.search ?? '').get('empresa');
    if (delLink && /^[a-z0-9][a-z0-9-]{1,38}$/.test(delLink)) {
      localStorage.setItem(CLAVE, delLink);
      return delLink;
    }
    return localStorage.getItem(CLAVE) ?? TIENDA_POR_DEFECTO;
  } catch {
    return TIENDA_POR_DEFECTO;
  }
}

export const tiendaActual = signal<string>(inicial());

export function elegirTienda(slug: string): void {
  tiendaActual.set(slug);
  try {
    localStorage.setItem(CLAVE, slug);
  } catch {
    // modo privado sin storage: vale para esta sesion
  }
}

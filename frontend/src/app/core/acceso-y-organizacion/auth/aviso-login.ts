const CLAVE = 'fashionstore.aviso_login';

/** Deja un mensaje para mostrar en el login despues de que la sesion se cerro sola (empresa
 * suspendida o suscripcion vencida). Vive en sessionStorage: se muestra una vez y se borra. */
export function guardarAvisoLogin(mensaje: string): void {
  try {
    sessionStorage.setItem(CLAVE, mensaje);
  } catch {
    // sin almacenamiento el aviso se pierde, pero la sesion igual se cierra
  }
}

export function tomarAvisoLogin(): string | null {
  try {
    const mensaje = sessionStorage.getItem(CLAVE);
    sessionStorage.removeItem(CLAVE);
    return mensaje;
  } catch {
    return null;
  }
}

import { HttpErrorResponse } from '@angular/common/http';

interface DetalleValidacion {
  loc?: (string | number)[];
  msg?: string;
}

/**
 * Traduce la respuesta de error de FastAPI a una linea legible. El backend manda el motivo real
 * en `detail` para 403/404/409/422, que es justo lo que el operador necesita leer.
 */
export function interpretarError(error: HttpErrorResponse, porDefecto = 'Ocurrió un error inesperado. Intentá de nuevo.'): string {
  if (error.status === 0) return 'No se pudo conectar con el servidor. Verificá tu conexión.';
  if (error.status === 401) return 'Tu sesión expiró. Iniciá sesión de nuevo.';

  const detalle = error.error?.detail;
  if (typeof detalle === 'string') return detalle;

  if (Array.isArray(detalle)) {
    const mensajes = (detalle as DetalleValidacion[])
      .map((item) => {
        const campo = item.loc?.filter((parte) => parte !== 'body').join('.');
        return campo ? `${campo}: ${item.msg}` : item.msg;
      })
      .filter(Boolean);
    if (mensajes.length) return mensajes.join(' · ');
  }

  if (error.status === 403) return 'Tu rol no tiene permiso para esta operación.';
  return porDefecto;
}

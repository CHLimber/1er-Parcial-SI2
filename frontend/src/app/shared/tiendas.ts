import { TiendaOut } from '../core/plataforma-saas/saas/saas.models';

/** SANTA_CRUZ -> Santa Cruz */
export function ciudadLegible(ciudad: string): string {
  return ciudad
    .toLowerCase()
    .split('_')
    .map((p) => p.charAt(0).toUpperCase() + p.slice(1))
    .join(' ');
}

/** "3 sucursales · Santa Cruz, La Paz" para la tarjeta de una tienda. */
export function resumenUbicacion(tienda: TiendaOut): string {
  const sucursales = `${tienda.sucursales} ${tienda.sucursales === 1 ? 'sucursal' : 'sucursales'}`;
  if (!tienda.ciudades.length) return sucursales;
  return `${sucursales} · ${tienda.ciudades.map(ciudadLegible).join(', ')}`;
}

export function resumenPrendas(tienda: TiendaOut): string {
  return `${tienda.prendas} ${tienda.prendas === 1 ? 'prenda' : 'prendas'}`;
}

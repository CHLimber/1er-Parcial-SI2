// apiUrl se reemplaza en build time (ver frontend/Dockerfile) con el ARG API_URL que Railway
// inyecta desde la variable de servicio del mismo nombre -- no editar el placeholder a mano.
export const environment = {
  production: true,
  apiUrl: '__API_URL__',
};

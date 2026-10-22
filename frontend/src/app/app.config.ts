import {
  ApplicationConfig,
  isDevMode,
  provideBrowserGlobalErrorListeners,
  provideZoneChangeDetection,
} from '@angular/core';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideRouter } from '@angular/router';
import { provideServiceWorker } from '@angular/service-worker';

import { routes } from './app.routes';
import { authInterceptor } from './core/acceso-y-organizacion/auth/auth.interceptor';
import { offlineInterceptor } from './core/operacion-sin-conexion/offline/offline.interceptor';

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideZoneChangeDetection({ eventCoalescing: true }),
    provideRouter(routes),
    // auth primero (adjunta el Bearer), despues offline (cache en IndexedDB + cola sin red)
    provideHttpClient(withInterceptors([authInterceptor, offlineInterceptor])),
    // PWA (PENDIENTES 5.1): el service worker cachea la app (ngsw-config.json) para que abra sin
    // red. Solo en build de produccion: en `ng serve` estorbaria el live reload.
    provideServiceWorker('ngsw-worker.js', {
      enabled: !isDevMode(),
      registrationStrategy: 'registerWhenStable:30000',
    }),
  ]
};

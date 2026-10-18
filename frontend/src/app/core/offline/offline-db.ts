/**
 * Base de datos temporal del navegador (Segundo parcial, PENDIENTES 5.2): IndexedDB propio, sin
 * dependencias. Dos almacenes:
 *   - `respuestas`: la ultima respuesta GET de la API por URL (catalogo, sucursales, mis compras,
 *     mis reservas, carrito...). La escribe y la lee offlineInterceptor: con red se refresca, sin
 *     red se sirve desde aca.
 *   - `cola`: operaciones que la clienta hizo sin conexion (agregar al carrito) y que
 *     ConexionService manda al backend cuando vuelve la red, en orden.
 * Es temporal: se vacia al cerrar sesion (los datos son del usuario logueado).
 *
 * Version 2 (operacion offline del personal, Modulos B y D) suma dos almacenes mas:
 *   - `paquete`: el subconjunto del catalogo de la sucursal bajado con GET /sync/catalogo
 *     (prendas, precios, existencias conocidas y cartera minima de clientas).
 *   - `operaciones`: ventas de contado y reservas registradas sin conexion, con su UUID y su
 *     estado de sincronizacion. NUNCA se borran por haberse enviado (RN12): pasan de
 *     REGISTRADA a ENVIADA y despues a CONFIRMADA / RECHAZADA / CONFLICTO segun responda el
 *     servidor. Sobreviven a cerrar el navegador; solo se pueden limpiar las ya cerradas.
 */

const NOMBRE_DB = 'fashionstore-offline';
const VERSION_DB = 2;

export interface RespuestaGuardada {
  url: string;
  cuerpo: unknown;
  guardadoEn: string;
}

export interface OperacionPendiente {
  id?: number;
  metodo: 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  url: string;
  cuerpo: unknown;
  descripcion: string;
  creadaEn: string;
}

let conexion: Promise<IDBDatabase> | null = null;

function abrir(): Promise<IDBDatabase> {
  conexion ??= new Promise((resolver, rechazar) => {
    if (typeof indexedDB === 'undefined') {
      rechazar(new Error('IndexedDB no disponible'));
      return;
    }
    const pedido = indexedDB.open(NOMBRE_DB, VERSION_DB);
    pedido.onupgradeneeded = () => {
      const db = pedido.result;
      if (!db.objectStoreNames.contains('respuestas')) db.createObjectStore('respuestas', { keyPath: 'url' });
      if (!db.objectStoreNames.contains('cola')) db.createObjectStore('cola', { keyPath: 'id', autoIncrement: true });
      if (!db.objectStoreNames.contains('paquete')) db.createObjectStore('paquete', { keyPath: 'clave' });
      if (!db.objectStoreNames.contains('operaciones')) db.createObjectStore('operaciones', { keyPath: 'id' });
    };
    pedido.onsuccess = () => resolver(pedido.result);
    pedido.onerror = () => {
      conexion = null;
      rechazar(pedido.error);
    };
  });
  return conexion;
}

async function operar<T>(almacen: string, modo: IDBTransactionMode, accion: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const db = await abrir();
  return new Promise((resolver, rechazar) => {
    const pedido = accion(db.transaction(almacen, modo).objectStore(almacen));
    pedido.onsuccess = () => resolver(pedido.result);
    pedido.onerror = () => rechazar(pedido.error);
  });
}

export const offlineDb = {
  guardarRespuesta(url: string, cuerpo: unknown): Promise<IDBValidKey> {
    const fila: RespuestaGuardada = { url, cuerpo, guardadoEn: new Date().toISOString() };
    return operar('respuestas', 'readwrite', (s) => s.put(fila));
  },

  leerRespuesta(url: string): Promise<RespuestaGuardada | undefined> {
    return operar<RespuestaGuardada | undefined>('respuestas', 'readonly', (s) => s.get(url));
  },

  encolar(operacion: Omit<OperacionPendiente, 'id' | 'creadaEn'>): Promise<IDBValidKey> {
    return operar('cola', 'readwrite', (s) => s.add({ ...operacion, creadaEn: new Date().toISOString() }));
  },

  pendientes(): Promise<OperacionPendiente[]> {
    return operar<OperacionPendiente[]>('cola', 'readonly', (s) => s.getAll());
  },

  quitar(id: number): Promise<undefined> {
    return operar('cola', 'readwrite', (s) => s.delete(id));
  },

  async limpiar(): Promise<void> {
    await operar('respuestas', 'readwrite', (s) => s.clear());
    await operar('cola', 'readwrite', (s) => s.clear());
    await operar('paquete', 'readwrite', (s) => s.clear());
    // las operaciones offline NO se borran al cerrar sesion: puede haber ventas sin sincronizar
    // (RN03/RN12). Quedan atadas a su usuario y se envian cuando el mismo vuelve a entrar.
  },

  // --- operacion offline del personal ---------------------------------------------------------

  guardarPaquete<T>(clave: string, datos: T): Promise<IDBValidKey> {
    return operar('paquete', 'readwrite', (s) => s.put({ clave, datos, guardadoEn: new Date().toISOString() }));
  },

  leerPaquete<T>(clave: string): Promise<{ clave: string; datos: T; guardadoEn: string } | undefined> {
    return operar('paquete', 'readonly', (s) => s.get(clave));
  },

  guardarOperacion<T extends { id: string }>(operacion: T): Promise<IDBValidKey> {
    return operar('operaciones', 'readwrite', (s) => s.put(operacion));
  },

  operaciones<T>(): Promise<T[]> {
    return operar<T[]>('operaciones', 'readonly', (s) => s.getAll());
  },

  quitarOperacion(id: string): Promise<undefined> {
    return operar('operaciones', 'readwrite', (s) => s.delete(id));
  },
};

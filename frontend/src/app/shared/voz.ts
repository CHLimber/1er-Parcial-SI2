// Web Speech API: sin tipos propios en el lib.dom.d.ts de TypeScript, se declara lo minimo que
// se usa. Solo Chrome/Edge lo implementan (con prefijo webkit); en Firefox/Safari sin soporte
// el constructor queda null y el boton de voz no se muestra (ver soportaVoz()).
//
// Compartido entre panel-reportes (CU15, "Reporte con IA") y asistente (CU18): a diferencia de
// los schemas de dominio (que cada modulo duplica a proposito, ver CLAUDE.md), esto es
// infraestructura de navegador sin logica de negocio, mismo criterio que shared/errores.ts.
export interface ResultadoVoz {
  results: { [indice: number]: { [alt: number]: { transcript: string } } };
}

export interface ReconocedorVoz {
  lang: string;
  interimResults: boolean;
  continuous: boolean;
  onresult: ((ev: ResultadoVoz) => void) | null;
  onerror: (() => void) | null;
  onend: (() => void) | null;
  start: () => void;
  stop: () => void;
}

export function obtenerConstructorVoz(): (new () => ReconocedorVoz) | null {
  const global = window as unknown as Record<string, unknown>;
  return (global['SpeechRecognition'] ?? global['webkitSpeechRecognition'] ?? null) as
    | (new () => ReconocedorVoz)
    | null;
}

export function soportaVoz(): boolean {
  return obtenerConstructorVoz() !== null;
}

/** Reconocedor listo para dictar una sola frase (sin resultados parciales), en es-BO. */
export function crearReconocedorVoz(): ReconocedorVoz | null {
  const Constructor = obtenerConstructorVoz();
  if (!Constructor) return null;
  const reconocedor = new Constructor();
  reconocedor.lang = 'es-BO';
  reconocedor.interimResults = false;
  reconocedor.continuous = false;
  return reconocedor;
}

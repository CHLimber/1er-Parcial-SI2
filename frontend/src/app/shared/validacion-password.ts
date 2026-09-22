import { AbstractControl, ValidationErrors, ValidatorFn } from '@angular/forms';

export interface ReglaPassword {
  clave: string;
  etiqueta: string;
  cumple: boolean;
}

// Espejo manual de REGLAS_PASSWORD en backend/app/modules/usuarios/politica_password.py.
// Si se cambia una regla ahi, hay que tocar esta lista y la de movil/lib/compartido/widgets.dart.
const REGLAS: { clave: string; etiqueta: string; prueba: (valor: string) => boolean }[] = [
  { clave: 'longitud', etiqueta: 'Al menos 8 caracteres', prueba: (v) => v.length >= 8 },
  { clave: 'minuscula', etiqueta: 'Una letra minúscula', prueba: (v) => /[a-z]/.test(v) },
  { clave: 'mayuscula', etiqueta: 'Una letra mayúscula', prueba: (v) => /[A-Z]/.test(v) },
  { clave: 'numero', etiqueta: 'Un número', prueba: (v) => /\d/.test(v) },
  { clave: 'especial', etiqueta: 'Un carácter especial (!@#$%...)', prueba: (v) => /[^\w\s]/.test(v) },
];

export function reglasPassword(valor: string | null | undefined): ReglaPassword[] {
  const texto = valor ?? '';
  return REGLAS.map(({ clave, etiqueta, prueba }) => ({ clave, etiqueta, cumple: prueba(texto) }));
}

export const passwordSeguraValidator: ValidatorFn = (control: AbstractControl): ValidationErrors | null => {
  const faltantes = reglasPassword(control.value).filter((regla) => !regla.cumple);
  return faltantes.length ? { passwordInsegura: faltantes.map((regla) => regla.clave) } : null;
};

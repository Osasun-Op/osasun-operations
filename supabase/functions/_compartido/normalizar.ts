// Normalización de nombres y lectura de números (REGLAS_CALCULO.md §1 y §2.1).
// Código puro: sin red ni base de datos.

/** Mayúsculas y sin ningún espacio: «v2 4 g» → «V24G». */
export function norm(texto: string): string {
  return texto.toUpperCase().replace(/\s+/g, "");
}

/** Celda de la hoja como texto recortado («» si no hay nada). */
export function celda(fila: unknown[] | undefined, columna: number): string {
  const valor = fila?.[columna];
  return valor === undefined || valor === null ? "" : String(valor).trim();
}

/**
 * Número de la hoja en centésimas exactas (entero), para calcular sin errores
 * de coma flotante. Acepta enteros, negativos y decimales con coma o punto.
 * Celda vacía o texto no numérico → null (dato no válido; nunca 0 sin avisar).
 */
export function centesimas(texto: string): number | null {
  const m = /^(-?)(\d+)(?:[.,](\d{1,2}))?$/.exec(texto.trim());
  if (!m) return null;
  const decimales = (m[3] ?? "").padEnd(2, "0");
  const valor = Number(m[2]) * 100 + Number(decimales);
  return m[1] === "-" ? -valor : valor;
}

/** Centésimas → texto con coma decimal: 250 → «2,5», -2700 → «-27». */
export function textoNumero(c: number): string {
  const signo = c < 0 ? "-" : "";
  const abs = Math.abs(c);
  const entero = Math.floor(abs / 100);
  const resto = abs % 100;
  if (resto === 0) return `${signo}${entero}`;
  return `${signo}${entero},${String(resto).padStart(2, "0").replace(/0$/, "")}`;
}

/** División entera hacia arriba para numerador y divisor positivos. */
export function divisionArriba(numerador: number, divisor: number): number {
  return Math.floor((numerador + divisor - 1) / divisor);
}

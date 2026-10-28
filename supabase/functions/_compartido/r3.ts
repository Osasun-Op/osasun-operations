// R3 · Stock del almacén (+35 %) (REGLAS_CALCULO.md §3). Código puro.
//   objetivo = 35 % del consumo semanal; cajas = objetivo − contador, si es
//   positivo, redondeado hacia arriba (D1). Orden: consumo de mayor a menor.

import type { DatosHoja } from "./hoja.ts";
import { centesimas, divisionArriba, norm, textoNumero } from "./normalizar.ts";
import type { Cajas } from "./pedidos.ts";

export interface ConfigR3 {
  porcentaje: number;                                              // 35
  excluidos: { producto: string; formato: string; motivo: string }[];
}

export interface ElementoStock {
  producto: string;
  formato: string;
  categoria: string | null;
  cajas: number;
  consumo: string;
  contador: string;
  objetivo: number;          // redondeado hacia arriba, solo para la frase
  en_camino?: number;        // R1c: cajas en camino a las tiendas que la hoja aún no cuenta (sumadas al contador)
  motivo: string;
  variedades?: { nombre: string; granel: string }[];
}

export interface ResultadoR3 {
  lista: ElementoStock[];
  /** «Sin granel no se produce»: X de la tarea «Avisa a Administración: falta X». */
  faltas: string[];
  /** Datos que no se han podido calcular (nunca se inventan). */
  avisos: string[];
  excluidos: { producto: string; formato: string; motivo: string }[];
}

const FIFO = "Usa primero el granel más antiguo (FIFO). Mínimo 2 variedades de invernadero y 2 de indoor.";

/** Cajas a hacer en centésimas exactas; 0 si ya está cubierto. */
export function cajasR3(consumo100: number, contador100: number, porcentaje = 35): number {
  const numerador = porcentaje * consumo100 - 100 * contador100; // en diezmilésimas de caja
  return numerador > 0 ? divisionArriba(numerador, 10000) : 0;
}

/**
 * R1c · Cajas de todas partes = hoja + lo producido desde el último recuento −
 * lo que ha salido del almacén desde entonces + lo que va en camino a las tiendas
 * (el reparto hasta las 23:30, el envío hasta las 11:59 del día siguiente). Lo
 * que sale en un pedido de Nacex no va a ninguna tienda: sale del stock.
 */
export interface AjusteStock {
  producto: string;
  formato: string;
  hechas?: number;      // producidas y marcadas desde el último recuento
  salidas?: number;     // salidas del almacén desde el último recuento
  en_camino?: number;   // en camino a una tienda
}

type Totales = { hechas: number; salidas: number; en_camino: number };

/**
 * Suma los ajustes por línea de CONTEO DE CAJAS TOTAL: cada referencia a la
 * suya; las variedades de Invernadero e Indoor, al total de su categoría
 * («INVERNADERO TOTAL» / «INDOOR TOTAL» del mismo formato).
 */
export function ajustesPorConteo(d: DatosHoja, ajustes: AjusteStock[]): Map<string, Totales> {
  const claves = new Set(d.conteo.map((c) => norm(c.producto + c.formato)));
  const invernadero = new Set(d.variedades.INVERNADERO.map(norm));
  const indoor = new Set(d.variedades.INDOOR.map(norm));
  const suma = new Map<string, Totales>();
  for (const e of ajustes) {
    let k = norm(e.producto + e.formato);
    if (!claves.has(k)) {
      const n = norm(e.producto);
      if (invernadero.has(n)) k = norm("INVERNADERO TOTAL" + e.formato);
      else if (indoor.has(n)) k = norm("INDOOR TOTAL" + e.formato);
    }
    if (!claves.has(k)) continue;
    const t = suma.get(k) ?? { hechas: 0, salidas: 0, en_camino: 0 };
    t.hechas += e.hechas ?? 0;
    t.salidas += e.salidas ?? 0;
    t.en_camino += e.en_camino ?? 0;
    suma.set(k, t);
  }
  return suma;
}

/** Ajustes de R3 con los movimientos del almacén y lo que va en camino. */
export function ajustesStock(
  m: { producido: Cajas[]; salido: Cajas[] },
  enCamino: Cajas[],
): AjusteStock[] {
  return [
    ...m.producido.map((c) => ({ producto: c.producto, formato: c.formato, hechas: c.cantidad })),
    ...m.salido.map((c) => ({ producto: c.producto, formato: c.formato, salidas: c.cantidad })),
    ...enCamino.map((c) => ({ producto: c.producto, formato: c.formato, en_camino: c.cantidad })),
  ];
}

/** Cómo se ha llegado al contador, en una frase: «(con 6 hechas desde el recuento y 5 en camino a las tiendas)». */
function explicacion(t: Totales | undefined): string {
  if (!t) return "";
  const partes: string[] = [];
  if (t.hechas > 0) partes.push(`${t.hechas} hechas desde el recuento`);
  const neto = t.en_camino - t.salidas;
  if (neto > 0) partes.push(`${neto} en camino a las tiendas`);
  if (neto < 0) partes.push(`sin ${-neto} que ya han salido`);
  if (partes.length === 0) return "";
  const ultima = partes.pop()!;
  return ` (con ${partes.length > 0 ? partes.join(", ") + " y " : ""}${ultima})`;
}

export function calcularStock(d: DatosHoja, cfg: ConfigR3, ajustes: AjusteStock[] = []): ResultadoR3 {
  const porNombre = new Map(d.productos.map((p) => [norm(p.nombre), p]));
  const excluidos = new Map(cfg.excluidos.map((e) => [norm(e.producto + e.formato), e]));
  const porConteo = ajustesPorConteo(d, ajustes);
  const resultado: ResultadoR3 = { lista: [], faltas: [], avisos: [], excluidos: [] };
  const candidatos: (ElementoStock & { consumo100: number; orden: number })[] = [];

  for (const c of d.conteo) {
    const nombre = c.producto.trim();
    const clave = norm(c.producto + c.formato);
    const excluido = excluidos.get(clave);
    if (excluido) {
      resultado.excluidos.push({ producto: nombre, formato: c.formato, motivo: excluido.motivo });
      continue;
    }
    const consumo100 = centesimas(c.consumo);
    const contadorHoja = centesimas(c.contador);
    const etiqueta = `${nombre}${c.formato ? " " + c.formato : ""}`;
    if (consumo100 === null || contadorHoja === null) {
      resultado.avisos.push(`No puedo calcular ${etiqueta}: dato vacío o no válido en CONTEO DE CAJAS TOTAL.`);
      continue;
    }
    const ajuste = porConteo.get(clave);
    const enCaminoRef = Math.max((ajuste?.en_camino ?? 0) - (ajuste?.salidas ?? 0), 0);
    const contador100 = contadorHoja + 100 * ((ajuste?.hechas ?? 0) - (ajuste?.salidas ?? 0) + (ajuste?.en_camino ?? 0));
    const cajas = cajasR3(consumo100, contador100, cfg.porcentaje);
    if (cajas <= 0) continue;

    const objetivo = divisionArriba(Math.max(cfg.porcentaje * consumo100, 0), 10000);
    const signo = contador100 >= 0 ? "+" : "";
    let motivo = `Se venden ${textoNumero(consumo100)} cajas a la semana. Tienes ${signo}${textoNumero(contador100)}` +
      explicacion(ajuste) + ` y el objetivo es +${objetivo}. Haz ${cajas}.`;

    const n = norm(nombre);
    const rota = n === "INVERNADEROTOTAL" ? "INVERNADERO" : n === "INDOORTOTAL" ? "INDOOR" : null;
    let producto = nombre;
    let categoria: string | null = d.categorias[n] ?? null;
    let variedades: { nombre: string; granel: string }[] | undefined;

    if (rota) {
      producto = rota === "INVERNADERO" ? "Invernadero" : "Indoor";
      categoria = producto;
      const todas = d.variedades[rota].map((v) => ({ nombre: v.trim(), granel: porNombre.get(norm(v))?.granel ?? "" }));
      const total = todas.reduce((s, v) => s + Math.max(centesimas(v.granel) ?? 0, 0), 0);
      variedades = todas.filter((v) => (centesimas(v.granel) ?? 0) > 0);
      if (total <= 0) {
        if (!resultado.faltas.includes(producto)) resultado.faltas.push(producto);
        continue;
      }
      motivo += ` Variedades con granel: ${variedades.map((v) => v.nombre).join(", ")}. ${FIFO}`;
    } else {
      const p = porNombre.get(n);
      if (!p) {
        resultado.avisos.push(`No puedo calcular ${etiqueta}: no está en PRINCIPAL.`);
        continue;
      }
      const granel = centesimas(p.granel);
      if (granel === null) {
        resultado.avisos.push(`No puedo calcular ${etiqueta}: el granel está vacío o no es un número en PRINCIPAL.`);
        continue;
      }
      if (granel <= 0) {
        if (!resultado.faltas.includes(nombre)) resultado.faltas.push(nombre);
        continue;
      }
    }

    candidatos.push({
      producto, formato: c.formato, categoria, cajas, consumo: c.consumo, contador: c.contador,
      objetivo, ...(enCaminoRef > 0 ? { en_camino: enCaminoRef } : {}), motivo, variedades, consumo100, orden: c.orden,
    });
  }

  candidatos.sort((a, b) => b.consumo100 - a.consumo100 || a.orden - b.orden);
  resultado.lista = candidatos.map(({ consumo100: _c, orden: _o, ...e }) => e);
  return resultado;
}

// R4 · Cobertura a 2 semanas (REGLAS_CALCULO.md §4). Código puro.
//   En cada producto: «LO QUE HAY EN TOTAL» de PRINCIPAL frente a 2 × «1 SEMANA
//   NECESIDADES». Invernadero e Indoor, sumando toda la categoría. Con la hoja
//   tal cual: producir o mandar a una tienda no cambia el total. Una sola cuenta
//   para el panel de Administración y para el aviso del jueves.

import type { DatosHoja } from "./hoja.ts";
import { centesimas, norm, textoNumero } from "./normalizar.ts";

export interface ProductoCobertura {
  producto: string;
  formato: string;            // la hoja da el total por producto: siempre ""
  total: number;
  necesidad_semana: number;
  semanas: number;            // total / necesidad, con un decimal hacia abajo
  motivo: string;
}

export interface ResultadoR4 {
  /** Solo los que están por debajo de 2 semanas, de menos a más semanas. */
  productos: ProductoCobertura[];
  /** Datos que no se han podido calcular (nunca se inventan). */
  avisos: string[];
}

const SEMANAS = 2;
const numero = (c: number) => c / 100;

/** Cobertura de cada producto; `excluidos`: los de `stock_excluidos` (minis y vapers), por nombre de producto. */
export function calcularCobertura(d: Pick<DatosHoja, "productos" | "variedades">, excluidos: { producto: string }[]): ResultadoR4 {
  const r: ResultadoR4 = { productos: [], avisos: [] };
  if (!d.productos.some((p) => p.total !== undefined)) {
    r.avisos.push("No encuentro las columnas «LO QUE HAY EN TOTAL» y «1 SEMANA NECESIDADES» en PRINCIPAL.");
    return r;
  }
  const fuera = new Set(excluidos.map((e) => norm(e.producto)));
  const categoria = new Map<string, string>();
  for (const v of d.variedades.INVERNADERO) categoria.set(norm(v), "Invernadero");
  for (const v of d.variedades.INDOOR) categoria.set(norm(v), "Indoor");

  // Grupos: cada producto que se reparte (como el catálogo) o su categoría.
  const grupos = new Map<string, { nombre: string; orden: number; total: number; necesidad: number; malos: string[] }>();
  for (const p of d.productos) {
    if (p.formatos.length === 0 && !p.conTiendas) continue; // materia prima, no se vende
    const nombre = p.nombre.trim();
    if (fuera.has(norm(nombre))) continue;
    const clave = categoria.get(norm(nombre)) ?? nombre;
    const g = grupos.get(clave) ?? { nombre: clave, orden: p.orden, total: 0, necesidad: 0, malos: [] };
    grupos.set(clave, g);
    const total = centesimas(p.total ?? "");
    const necesidad = centesimas(p.necesidad ?? "");
    if (total === null || necesidad === null) g.malos.push(`${nombre}: dato vacío o no válido`);
    else if (total < 0) g.malos.push(`${nombre}: el total es negativo (${p.total})`);
    else if (necesidad < 0) g.malos.push(`${nombre}: la necesidad es negativa (${p.necesidad})`);
    else {
      g.total += total;
      g.necesidad += necesidad;
    }
  }

  for (const g of [...grupos.values()].sort((a, b) => a.orden - b.orden)) {
    if (g.malos.length > 0) {
      r.avisos.push(`No puedo calcular ${g.nombre} en PRINCIPAL (${g.malos.join("; ")}).`);
      continue;
    }
    if (g.necesidad === 0 || g.total >= SEMANAS * g.necesidad) continue;
    const semanas = Math.floor((10 * g.total) / g.necesidad) / 10;
    r.productos.push({
      producto: g.nombre, formato: "", total: numero(g.total), necesidad_semana: numero(g.necesidad), semanas,
      motivo: `Hay ${textoNumero(g.total)} en total y se necesitan ${textoNumero(g.necesidad)} a la semana: ` +
        `da para ${String(semanas).replace(".", ",")} semanas.`,
    });
  }
  r.productos.sort((a, b) => a.semanas - b.semanas);
  return r;
}

type Rpc = <T = unknown>(nombre: string, args: Record<string, unknown>) => Promise<T>;

/**
 * Guarda la cobertura con la lectura de la hoja (lecturas_sheets.cobertura), para
 * el panel (estado_actual.cobertura_baja). Si falla, no para el reparto ni el
 * stock: el panel enseña la última que haya.
 */
export async function guardarCobertura(
  rpc: Rpc, lectura: string, datos: Pick<DatosHoja, "productos" | "variedades">, excluidos: { producto: string }[],
): Promise<void> {
  try {
    await rpc("servidor_guardar_cobertura", { p_lectura: lectura, p_cobertura: calcularCobertura(datos, excluidos) });
  } catch (e) {
    console.error(e);
  }
}

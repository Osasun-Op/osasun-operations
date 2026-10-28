// R3 · Stock del almacén (+35 %) (REGLAS_CALCULO.md §3). Código puro.
//   objetivo = 35 % del consumo semanal; cajas = objetivo − contador, si es
//   positivo, redondeado hacia arriba (D1). Orden: consumo de mayor a menor.

import type { DatosHoja } from "./hoja.ts";
import { centesimas, divisionArriba, norm, textoNumero } from "./normalizar.ts";

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
  en_camino?: number;        // R1c: cajas en camino a las tiendas sumadas al contador
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
 * R1c · Cajas en camino: lo que ha salido hoy hacia las tiendas y el recuento ya
 * ha quitado del almacén, pero la tienda aún no ha apuntado. Se suman al
 * contador de su referencia; las variedades de Invernadero e Indoor, al total
 * de su categoría («INVERNADERO TOTAL» / «INDOOR TOTAL» del mismo formato).
 */
export function cajasEnCamino(d: DatosHoja, enCamino: { producto: string; formato: string; cantidad: number }[]) {
  const claves = new Set(d.conteo.map((c) => norm(c.producto + c.formato)));
  const invernadero = new Set(d.variedades.INVERNADERO.map(norm));
  const indoor = new Set(d.variedades.INDOOR.map(norm));
  const suma = new Map<string, number>();
  for (const e of enCamino) {
    let k = norm(e.producto + e.formato);
    if (!claves.has(k)) {
      const n = norm(e.producto);
      if (invernadero.has(n)) k = norm("INVERNADERO TOTAL" + e.formato);
      else if (indoor.has(n)) k = norm("INDOOR TOTAL" + e.formato);
    }
    if (claves.has(k)) suma.set(k, (suma.get(k) ?? 0) + e.cantidad);
  }
  return suma;
}

export function calcularStock(
  d: DatosHoja,
  cfg: ConfigR3,
  enCamino: { producto: string; formato: string; cantidad: number }[] = [],
): ResultadoR3 {
  const porNombre = new Map(d.productos.map((p) => [norm(p.nombre), p]));
  const excluidos = new Map(cfg.excluidos.map((e) => [norm(e.producto + e.formato), e]));
  const camino = cajasEnCamino(d, enCamino);
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
    const enCaminoRef = camino.get(clave) ?? 0;
    const contador100 = contadorHoja + 100 * enCaminoRef;
    const cajas = cajasR3(consumo100, contador100, cfg.porcentaje);
    if (cajas <= 0) continue;

    const objetivo = divisionArriba(Math.max(cfg.porcentaje * consumo100, 0), 10000);
    const signo = contador100 >= 0 ? "+" : "";
    let motivo = `Se venden ${textoNumero(consumo100)} cajas a la semana. Tienes ${signo}${textoNumero(contador100)}` +
      (enCaminoRef > 0 ? ` (con ${enCaminoRef} en camino a las tiendas)` : "") +
      ` y el objetivo es +${objetivo}. Haz ${cajas}.`;

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

// Almacén ahora (ESTADO_DEL_SISTEMA.md v1.27, §5 R1c; REGLAS_CALCULO.md §2.10).
// Código puro. La hoja solo cambia con los recuentos: la app suma lo producido y
// marcado desde el último recuento y resta lo que ha salido (bolsas listas, envío
// preparado, pedidos de Nacex preparados). Los movimientos los da la base de
// datos (servidor_preparar.almacen); aquí se aplican a lo leído en la hoja.

import type { EntradaCatalogo } from "./r1.ts";
import type { Cajas } from "./pedidos.ts";
import { centesimas, norm, textoNumero } from "./normalizar.ts";

/** Movimientos del almacén desde el último recuento (servidor_preparar.almacen). */
export interface MovimientosAlmacen {
  recuento_en: string | null;
  producido: Cajas[];
  /** Lo producido para el propio reparto o envío de hoy: ya está en sus elementos (se conserva lo hecho). */
  producido_reparto: Cajas[];
  producido_envio: Cajas[];
  salido: Cajas[];
}

export const SIN_MOVIMIENTOS: MovimientosAlmacen = {
  recuento_en: null, producido: [], producido_reparto: [], producido_envio: [], salido: [],
};

const clave = (producto: string, formato: string) => norm(producto + formato);

/** Suma cajas por referencia (con signo). */
export function sumar(mapa: Map<string, number>, cajas: Cajas[], signo = 1) {
  for (const c of cajas) {
    const k = clave(c.producto, c.formato);
    mapa.set(k, (mapa.get(k) ?? 0) + signo * c.cantidad);
  }
  return mapa;
}

/**
 * Lo que hay que sumar a la hoja para tener el almacén ahora, al calcular el
 * reparto o el envío: lo producido desde el recuento (sin lo producido para él
 * mismo, que ya cuenta como hecho en sus elementos) − lo que ha salido.
 */
export function ajusteAlmacen(m: MovimientosAlmacen, tipo: "reparto" | "envio"): Map<string, number> {
  const ajuste = sumar(new Map(), m.producido);
  sumar(ajuste, tipo === "reparto" ? m.producido_reparto : m.producido_envio, -1);
  return sumar(ajuste, m.salido, -1);
}

/**
 * El catálogo con el almacén ahora: la cifra de la hoja más el ajuste (en cajas).
 * Una celda vacía o con texto se queda como está si no hay movimiento (R1 avisa
 * y cuenta 0); si lo hay, se parte de 0. Una negativa cuenta como 0.
 */
export function aplicarAjuste(entradas: EntradaCatalogo[], ajuste: Map<string, number>): EntradaCatalogo[] {
  return entradas.map((e) => {
    const d = ajuste.get(clave(e.producto, e.formato)) ?? 0;
    if (d === 0) return e;
    const c = centesimas(e.almacen);
    const base = c === null ? 0 : Math.max(c, 0);
    return { ...e, almacen: textoNumero(Math.max(base + 100 * d, 0)) };
  });
}

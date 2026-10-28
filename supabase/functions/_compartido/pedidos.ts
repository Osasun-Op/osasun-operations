// Pedidos de cliente (ESTADO_DEL_SISTEMA.md v1.24, §5 R1b y R1c). Código puro.
// Cada referencia del pedido dice «Coge N del almacén» (si quedan cajas en el
// almacén después de apartar lo comprometido hoy) o «Haz N» (REGLAS_CALCULO.md §2.10).

import type { EntradaCatalogo } from "./r1.ts";
import { centesimas, norm } from "./normalizar.ts";

export interface Cajas {
  producto: string;
  formato: string;
  cantidad: number;
}

export interface ElementoPedido extends Cajas {
  coge: number;
  haz: number;
  en_almacen: number;   // lo que queda en el almacén para este pedido (ya apartado lo comprometido)
  motivo: string;
  orden: number;
  categoria?: string;
}

/**
 * Lo comprometido hoy que la hoja aún cuenta en el almacén (motor.comprometido).
 * `en_camino`: lo que ya ha salido hacia las tiendas y el recuento ya ha quitado
 * del almacén (para R3).
 */
export interface Comprometido {
  reparto: Cajas[];
  pedidos_tienda: Cajas[];
  envio: Cajas[];
  pedidos_nacex: Cajas[];
  en_camino: Cajas[];
}

export const SIN_COMPROMISOS: Comprometido = { reparto: [], pedidos_tienda: [], envio: [], pedidos_nacex: [], en_camino: [] };

export const textoCogeHaz = (coge: number, haz: number) =>
  coge > 0 && haz > 0 ? `Coge ${coge} del almacén y haz ${haz}` : coge > 0 ? `Coge ${coge} del almacén` : `Haz ${haz}`;

/** Cajas del almacén según la hoja (vacío o negativo: 0, como en R1). */
function almacen(entradas: EntradaCatalogo[]) {
  const m = new Map<string, { cajas: number; orden: number }>();
  for (const e of entradas) {
    const c = centesimas(e.almacen);
    m.set(norm(e.producto + e.formato), { cajas: c === null || c < 0 ? 0 : Math.floor(c / 100), orden: e.orden });
  }
  return m;
}

const sumar = (m: Map<string, number>, lineas: Cajas[]) => {
  for (const l of lineas) m.set(norm(l.producto + l.formato), (m.get(norm(l.producto + l.formato)) ?? 0) + l.cantidad);
};

/**
 * «Coge / haz» de un pedido: lo que queda en el almacén es lo de la hoja menos lo
 * comprometido antes que él (sin bajar de 0). Coge lo que haya; el resto, haz.
 */
export function cogeHaz(lineas: Cajas[], entradas: EntradaCatalogo[], antes: Cajas[], categorias: Record<string, string> = {}): ElementoPedido[] {
  const alm = almacen(entradas);
  const usado = new Map<string, number>();
  sumar(usado, antes);
  return lineas.map((l) => {
    const k = norm(l.producto + l.formato);
    const disponible = Math.max(0, (alm.get(k)?.cajas ?? 0) - (usado.get(k) ?? 0));
    const coge = Math.min(l.cantidad, disponible);
    const haz = l.cantidad - coge;
    usado.set(k, (usado.get(k) ?? 0) + l.cantidad);
    return {
      producto: l.producto, formato: l.formato, cantidad: l.cantidad, coge, haz, en_almacen: disponible,
      motivo: textoCogeHaz(coge, haz), orden: alm.get(k)?.orden ?? 0,
      ...(categorias[norm(l.producto)] ? { categoria: categorias[norm(l.producto)] } : {}),
    };
  });
}

/**
 * Pedidos para recoger en tienda que van en el reparto: primero lo oficial (el
 * envío y los pedidos de Nacex de hoy y el propio reparto) y después cada pedido,
 * en orden de llegada.
 */
export function planPedidosTienda(
  pedidos: { id: string; lineas: Cajas[] }[],
  entradas: EntradaCatalogo[],
  oficial: Cajas[],
  categorias: Record<string, string> = {},
): { pedido_id: string; elementos: ElementoPedido[] }[] {
  const antes = [...oficial];
  return pedidos.map((p) => {
    const elementos = cogeHaz(p.lineas, entradas, antes, categorias);
    antes.push(...p.lineas);
    return { pedido_id: p.id, elementos };
  });
}

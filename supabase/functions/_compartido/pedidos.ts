// Pedidos de cliente (ESTADO_DEL_SISTEMA.md v1.24, §5 R1b y R1c). Código puro.
// La lista del pedido y lo comprometido ese día. El «coge / haz» de cada
// referencia lo calcula la base de datos al salir la tarea de prepararlo
// (motor.calcular_pedido, REGLAS_CALCULO.md §2.10).

import type { EntradaCatalogo } from "./r1.ts";
import { norm } from "./normalizar.ts";

export interface Cajas {
  producto: string;
  formato: string;
  cantidad: number;
}

export interface ElementoPedido extends Cajas {
  orden: number;        // orden de la hoja
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

/** Lista de un pedido con el orden de la hoja y la categoría (el «coge / haz» lo pone la base de datos al salir la tarea). */
export function listaPedido(lineas: Cajas[], entradas: EntradaCatalogo[], categorias: Record<string, string> = {}): ElementoPedido[] {
  const orden = new Map(entradas.map((e) => [norm(e.producto + e.formato), e.orden]));
  return lineas.map((l) => ({
    producto: l.producto, formato: l.formato, cantidad: l.cantidad, orden: orden.get(norm(l.producto + l.formato)) ?? 0,
    ...(categorias[norm(l.producto)] ? { categoria: categorias[norm(l.producto)] } : {}),
  }));
}

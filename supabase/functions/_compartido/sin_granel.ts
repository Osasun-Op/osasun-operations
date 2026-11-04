// R1e · Producto sin granel en el reparto (ESTADO_DEL_SISTEMA.md v1.30, §5 R1e;
// REGLAS_CALCULO.md §2.11). Código puro. Al calcular la producción del reparto,
// cada referencia que hay que hacer y cuyo producto no tiene granel (≤ 0 en
// PRINCIPAL, el mismo criterio que R3) se marca `sin_granel`, con las tiendas
// que la reciben (`para`) y las demás tiendas del reparto que tienen cajas
// (`tiendas_con_stock`, de sus columnas en PRINCIPAL). Qué se hace con ella
// (quitarla o cogerla de otra tienda) lo decide el operario en la producción.

import type { DatosHoja } from "./hoja.ts";
import type { Bolsa, Destino, ElementoProduccion } from "./r1.ts";
import { centesimas, norm } from "./normalizar.ts";

/** Cajas de una tienda según su columna de PRINCIPAL (por su código o sus alias); null si no la hay. */
function cajasEnTienda(tiendas: Record<string, string> | undefined, d: Destino & { codigo?: string }): number | null {
  if (!tiendas) return null;
  const nombres = new Set([d.codigo ?? "", ...d.alias].map(norm));
  const columna = Object.keys(tiendas).find((k) => nombres.has(norm(k)));
  const c = columna === undefined ? null : centesimas(tiendas[columna]);
  return c === null ? null : Math.floor(c / 100);
}

/**
 * Marca las referencias sin granel de la producción del reparto. `destinos`: las
 * tiendas del reparto, en su orden. Lo que hay en el almacén se reparte entre las
 * tiendas que lo reciben en ese orden: a las últimas es a las que les falta.
 */
export function marcarSinGranel(
  produccion: ElementoProduccion[], bolsas: Bolsa[], datos: Pick<DatosHoja, "productos">,
  destinos: (Destino & { codigo?: string })[],
): ElementoProduccion[] {
  const porNombre = new Map(datos.productos.map((p) => [norm(p.nombre), p]));
  return produccion.map((e) => {
    const p = porNombre.get(norm(e.producto));
    const granel = p ? centesimas(p.granel) : null;
    if (e.faltan <= 0 || !p || granel === null || granel > 0) return e;

    let queda = e.en_almacen;
    const para: NonNullable<ElementoProduccion["para"]> = [];
    for (const d of destinos) {
      const item = bolsas.find((b) => b.destino_id === d.id)?.items
        .find((i) => i.producto === e.producto && i.formato === e.formato);
      if (!item) continue;
      const delAlmacen = Math.min(queda, item.cantidad);
      queda -= delAlmacen;
      para.push({ destino_id: d.id, destino: d.nombre, pedido: item.cantidad, faltan: item.cantidad - delAlmacen });
    }
    const tiendas = e.formato === "" ? p.tiendas : p.formatos.find((f) => norm(f.formato) === norm(e.formato))?.tiendas;
    const tiendas_con_stock = destinos
      .filter((d) => !para.some((x) => x.destino_id === d.id))
      .map((d) => ({ destino_id: d.id, destino: d.nombre, cajas: cajasEnTienda(tiendas, d) ?? 0 }))
      .filter((t) => t.cajas > 0);
    return { ...e, sin_granel: true, para: para.filter((x) => x.faltan > 0), tiendas_con_stock };
  });
}

/** Una referencia del envío que no se puede mandar entera (R1e en el envío). */
export interface SinGranelEnvio {
  destino_id: string;
  destino: string;
  producto: string;
  formato: string;
  pedido: number;
  hay: number;          // lo máximo que se puede mandar con las cajas que hay
  mensaje: string;
}

const cajas = (n: number) => `${n} ${n === 1 ? "caja" : "cajas"}`;

/**
 * R1e en el envío (ESTADO v1.31): se comprueba al calcular, no en la producción,
 * porque no hay ruta que pase por otra tienda. Con la misma cuenta que decide lo
 * que falta (con la cifra de almacén de la hoja, R1c v1.58): lo que hay que hacer sin
 * granel. Las cajas que hay se las llevan los primeros destinos, en su orden.
 */
export function sinGranelEnvio(
  produccion: ElementoProduccion[], bolsas: Bolsa[], datos: Pick<DatosHoja, "productos">,
  destinos: (Destino & { codigo?: string })[],
): SinGranelEnvio[] {
  return marcarSinGranel(produccion, bolsas, datos, destinos).flatMap((e) =>
    (e.para ?? []).map((p) => {
      const hay = p.pedido - p.faltan;
      const ref = `${e.producto}${e.formato ? " " + e.formato : ""}`;
      const mensaje = hay > 0
        ? `${ref}: pides ${p.pedido}, en el almacén hay ${cajas(hay)} y no hay granel para hacer ${p.faltan === 1 ? "la otra" : `las otras ${p.faltan}`}.`
        : `${ref}: pides ${p.pedido}, en el almacén no hay cajas y no hay granel para hacer${p.pedido === 1 ? "la" : "las"}.`;
      return { destino_id: p.destino_id, destino: p.destino, producto: e.producto, formato: e.formato,
               pedido: p.pedido, hay, mensaje };
    })
  );
}

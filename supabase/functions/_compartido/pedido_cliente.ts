// Función del servidor `guardar_pedido_cliente` (CONTRATOS.md §3.16). La lógica
// va aquí, con la hoja y la base de datos recibidas desde fuera, para probarla
// sin red (pedido_cliente_test.ts). El index.ts solo la conecta.

import { referencias, validarLineas } from "./lista.ts";
import { listaPedido } from "./pedidos.ts";
import type { Dependencias } from "./reparto_lista.ts";
import type { Pestanas, ResultadoLectura } from "./google.ts";

type Respuesta = Record<string, unknown>;

interface Preparado {
  error?: { codigo: string; mensaje: string };
  previo?: Respuesta;
  fecha: string;
  jornada_id: string | null;
  /** Recoger en tienda con el reparto de hoy ya guardado y las bolsas sin terminar: entra en él al momento. */
  reparto_id?: string | null;
  config: { sheets_documento_id: string; sheets_pestanas: Pestanas };
}

const error = (codigo: string, mensaje: string, extra: Record<string, unknown> = {}): Respuesta =>
  ({ error: { codigo, mensaje, ...extra } });

const errorHoja = (l: Extract<ResultadoLectura, { ok: false }>) =>
  error(l.codigo, l.codigo === "SHEETS_NO_DISPONIBLE"
    ? "No puedo leer la hoja de stock ahora. Vuelve a intentarlo en un minuto; si sigue, avisa a Administración."
    : "La hoja de stock ha cambiado de forma. Avisa a Administración.", { detalle: l.detalle });

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PEDIDO = "pedido";   // destino ficticio para validar la lista (el pedido no va por tiendas)

/** guardar_pedido_cliente(id_cliente, lineas, entrega, destino_id?, cliente, datos_envio?). */
export async function guardarPedidoClienteDe(d: Dependencias, persona: string, cuerpo: Record<string, unknown>): Promise<Respuesta> {
  const idCliente = typeof cuerpo.id_cliente === "string" && UUID.test(cuerpo.id_cliente) ? cuerpo.id_cliente : null;
  const entrega = cuerpo.entrega === "tienda" || cuerpo.entrega === "nacex" ? cuerpo.entrega : null;
  const cliente = typeof cuerpo.cliente === "string" ? cuerpo.cliente.replace(/\s+/g, " ").trim() : "";
  const destino = typeof cuerpo.destino_id === "string" && UUID.test(cuerpo.destino_id) ? cuerpo.destino_id : null;
  const datosEnvio = typeof cuerpo.datos_envio === "string" ? cuerpo.datos_envio.trim() : "";
  if (!idCliente) return error("DATOS_NO_VALIDOS", "Falta el id_cliente del pedido.");
  if (!entrega) return error("DATOS_NO_VALIDOS", "Elige cómo se entrega: recoger en tienda o envío por Nacex.");
  if (!cliente) return error("DATOS_NO_VALIDOS", "Escribe el nombre del cliente.");
  if (cliente.length > 60) return error("DATOS_NO_VALIDOS", "El nombre del cliente es demasiado largo (60 letras como máximo).");
  if (entrega === "tienda" && !destino) return error("DATOS_NO_VALIDOS", "Elige la tienda donde lo recoge.");
  if (entrega === "nacex" && !datosEnvio) return error("DATOS_NO_VALIDOS", "Pega los datos de envío (nombre, dirección, teléfono…).");
  if (datosEnvio.length > 1000) return error("DATOS_NO_VALIDOS", "Los datos de envío son demasiado largos.");

  const prep = await d.rpc<Preparado>("servidor_preparar_pedido", {
    p_persona: persona, p_id_cliente: idCliente, p_entrega: entrega, p_destino: destino,
  });
  if (prep.error) return prep as unknown as Respuesta;
  // Reintento de la misma petición: lo guardado, sin volver a leer la hoja.
  if (prep.previo) {
    return { pedido: prep.previo, ya_guardado: true,
             aviso: { codigo: "PEDIDO_YA_GUARDADO", mensaje: "Este pedido ya estaba guardado." } };
  }

  const lectura = await d.leer(prep.config.sheets_documento_id, prep.config.sheets_pestanas);
  const lecturaId = await d.rpc<string>("servidor_guardar_lectura", {
    p_persona: persona, p_motivo: "pedido", p_correcto: lectura.ok,
    p_error: lectura.ok ? null : `${lectura.codigo}: ${lectura.detalle}`,
    p_datos: lectura.ok ? lectura.datos : {},
  });
  if (!lectura.ok) return errorHoja(lectura);

  const { entradas, ambiguas } = referencias(lectura.datos);
  if (ambiguas.length > 0) {
    return error("CATALOGO_AMBIGUO", "Hay nombres repetidos en PRINCIPAL. Avisa a Administración.", { claves: ambiguas });
  }
  const lineas = Array.isArray(cuerpo.lineas)
    ? (cuerpo.lineas as Record<string, unknown>[]).map((l) => ({ ...l, destino_id: PEDIDO }))
    : cuerpo.lineas;
  const v = validarLineas(lineas, entradas, [{ id: PEDIDO, nombre: "Pedido", alias: [] }]);
  if (!v.ok) {
    return v.codigo === "DATOS_NO_VALIDOS" && v.mensaje.startsWith("Esa tienda")
      ? error("DATOS_NO_VALIDOS", "Revisa la lista del pedido.")
      : error(v.codigo, v.mensaje, v.detalle);
  }
  const cajas = v.lineas.map(({ producto, formato, cantidad }) => ({ producto, formato, cantidad }));

  // Nacex: su tarea, con la lista en el orden de la hoja. Recoger en tienda: la
  // tarea se crea al guardar el reparto que lo lleva (o ahora, si el de hoy ya
  // está guardado y las bolsas no están listas). El «coge / haz» se calcula al
  // salir la tarea.
  const lista = listaPedido(cajas, entradas, lectura.datos.categorias);
  const guardado = await d.rpc<Respuesta>("servidor_guardar_pedido_cliente", {
    p_persona: persona, p_id_cliente: idCliente, p_cliente: cliente, p_entrega: entrega,
    p_destino: entrega === "tienda" ? destino : null, p_datos_envio: entrega === "nacex" ? datosEnvio : null,
    p_lineas: cajas, p_fecha: prep.fecha, p_jornada: prep.jornada_id, p_lectura: lecturaId,
    p_elementos: entrega === "nacex" ? lista : null,
  });
  if (entrega !== "tienda" || !prep.reparto_id || guardado.error || guardado.ya_guardado) return guardado;
  const pedido = guardado.pedido as { id: string };
  const asignados = await d.rpc<{ pedidos: Respuesta[] }>("servidor_asignar_pedidos", {
    p_persona: persona, p_reparto: prep.reparto_id, p_pedidos: [{ pedido_id: pedido.id, elementos: lista }],
  });
  return { ...guardado, pedido: asignados.pedidos?.[0] ?? guardado.pedido };
}

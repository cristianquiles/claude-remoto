// Buzón de tareas entre el operador (Cris) y los agentes de los equipos cliente.
//
// Operador (Authorization: Bearer ADMIN_TOKEN)
//   POST   /admin/equipos               {nombre}          → {nombre, token}   (el token solo se ve una vez)
//   GET    /admin/equipos                                 → lista con estado en línea
//   GET    /admin/equipos/:nombre                         → detalle
//   DELETE /admin/equipos/:nombre                         → baja (revoca el token)
//   POST   /admin/tareas                {equipo, prompt, modo}
//   GET    /admin/tareas/:id
//
// Agente (Authorization: Bearer <token del equipo>)
//   GET    /agente/hola        → {nombre}  (valida el token, no toca la cola)
//   GET    /agente/siguiente   cabeceras X-Estado (activo|pausado) y X-Info (JSON)
//                              → 200 con una tarea, o 204 tras ~20 s sin nada (long-poll)
//   POST   /agente/resultado   {id, estado: hecha|error, resultado}

const EN_LINEA_MS = 60_000;
const ESPERA_MS = 20_000;
const SONDEO_MS = 2_000;
const MAX_RESULTADO = 1_000_000;
const MAX_PROMPT = 200_000;
const RETENCION_MS = 7 * 24 * 3600_000;

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
const error = (status, mensaje) => json({ error: mensaje }, status);

async function sha256(texto) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(texto));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function tokenAleatorio() {
  const b = crypto.getRandomValues(new Uint8Array(32));
  return "cre_" + btoa(String.fromCharCode(...b)).replace(/[+/=]/g, (c) => ({ "+": "-", "/": "_", "=": "" })[c]);
}

function iguales(a, b) {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  if (ea.length !== eb.length) return false;
  return crypto.subtle.timingSafeEqual(ea, eb);
}

function bearer(request) {
  const h = request.headers.get("authorization") || "";
  return h.startsWith("Bearer ") ? h.slice(7).trim() : "";
}

function vistaEquipo(e) {
  const ahora = Date.now();
  return {
    nombre: e.nombre,
    en_linea: !!e.ultimo_contacto && ahora - e.ultimo_contacto < EN_LINEA_MS,
    estado: e.estado || "sin conectar",
    ultimo_contacto: e.ultimo_contacto ? new Date(e.ultimo_contacto).toISOString() : null,
    info: e.info ? JSON.parse(e.info) : null,
  };
}

const NOMBRE_VALIDO = /^[a-z0-9][a-z0-9-]{0,39}$/;

async function admin(request, env, ruta) {
  if (!env.ADMIN_TOKEN || !iguales(bearer(request), env.ADMIN_TOKEN)) return error(401, "no autorizado");
  const db = env.DB;
  const m = request.method;

  if (ruta[1] === "equipos") {
    const nombre = ruta[2];
    if (!nombre && m === "POST") {
      const body = await request.json().catch(() => ({}));
      const n = String(body.nombre || "").toLowerCase();
      if (!NOMBRE_VALIDO.test(n)) return error(400, "nombre no válido (minúsculas, números y guiones)");
      const token = tokenAleatorio();
      const r = await db
        .prepare("INSERT INTO equipos (nombre, token_hash, creado) VALUES (?, ?, ?) ON CONFLICT(nombre) DO NOTHING")
        .bind(n, await sha256(token), Date.now())
        .run();
      if (!r.meta.changes) return error(409, "ya existe un equipo con ese nombre (dalo de baja antes)");
      return json({ nombre: n, token }, 201);
    }
    if (!nombre && m === "GET") {
      const { results } = await db.prepare("SELECT * FROM equipos ORDER BY nombre").all();
      return json(results.map(vistaEquipo));
    }
    if (nombre && m === "GET") {
      const e = await db.prepare("SELECT * FROM equipos WHERE nombre = ?").bind(nombre).first();
      return e ? json(vistaEquipo(e)) : error(404, "no existe ese equipo");
    }
    if (nombre && m === "DELETE") {
      await db.batch([
        db.prepare("DELETE FROM tareas WHERE equipo = ?").bind(nombre),
        db.prepare("DELETE FROM equipos WHERE nombre = ?").bind(nombre),
      ]);
      return json({ ok: true });
    }
  }

  if (ruta[1] === "tareas") {
    const id = ruta[2];
    if (!id && m === "POST") {
      const body = await request.json().catch(() => ({}));
      const modo = body.modo || "tarea";
      if (!["tarea", "continuar", "comprobar"].includes(modo)) return error(400, "modo no válido");
      const prompt = String(body.prompt || (modo === "comprobar" ? "comprobar" : ""));
      if (!prompt) return error(400, "tarea vacía");
      if (prompt.length > MAX_PROMPT) return error(413, "tarea demasiado larga");
      const e = await db.prepare("SELECT * FROM equipos WHERE nombre = ?").bind(body.equipo).first();
      if (!e) return error(404, "no existe ese equipo");
      if (e.estado === "pausado") return error(409, "el cliente ha pausado el acceso remoto");
      const nueva = crypto.randomUUID();
      const ahora = Date.now();
      await db
        .prepare("INSERT INTO tareas (id, equipo, modo, prompt, estado, creado, actualizado) VALUES (?, ?, ?, ?, 'pendiente', ?, ?)")
        .bind(nueva, e.nombre, modo, prompt, ahora, ahora)
        .run();
      return json({ id: nueva, equipo: vistaEquipo(e) }, 201);
    }
    if (id && m === "GET") {
      const t = await db.prepare("SELECT id, equipo, modo, estado, resultado, creado, actualizado FROM tareas WHERE id = ?").bind(id).first();
      return t ? json(t) : error(404, "no existe esa tarea");
    }
  }
  return error(404, "ruta desconocida");
}

async function agente(request, env, ruta) {
  const token = bearer(request);
  if (!token) return error(401, "no autorizado");
  const db = env.DB;
  const e = await db.prepare("SELECT * FROM equipos WHERE token_hash = ?").bind(await sha256(token)).first();
  if (!e) return error(401, "token no válido o equipo dado de baja");

  if (ruta[1] === "hola" && request.method === "GET") {
    return json({ nombre: e.nombre });
  }

  if (ruta[1] === "siguiente" && request.method === "GET") {
    const estado = request.headers.get("x-estado") === "pausado" ? "pausado" : "activo";
    let info = e.info;
    try {
      const b64 = request.headers.get("x-info"); // JSON en UTF-8 codificado en base64
      if (b64) info = JSON.stringify(JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)))));
    } catch { /* se conserva la última info válida */ }
    const tocar = db.prepare("UPDATE equipos SET ultimo_contacto = ?, estado = ?, info = ? WHERE nombre = ?");
    await tocar.bind(Date.now(), estado, info, e.nombre).run();
    if (estado === "pausado") return new Response(null, { status: 204 });

    const limite = Date.now() + ESPERA_MS;
    while (true) {
      const t = await db
        .prepare(
          `UPDATE tareas SET estado = 'en_curso', actualizado = ?1
           WHERE id = (SELECT id FROM tareas WHERE equipo = ?2 AND estado = 'pendiente' ORDER BY creado LIMIT 1)
           RETURNING id, modo, prompt`
        )
        .bind(Date.now(), e.nombre)
        .first();
      if (t) return json(t);
      if (Date.now() + SONDEO_MS > limite) break;
      await new Promise((r) => setTimeout(r, SONDEO_MS));
    }
    await tocar.bind(Date.now(), estado, info, e.nombre).run();
    return new Response(null, { status: 204 });
  }

  if (ruta[1] === "resultado" && request.method === "POST") {
    const body = await request.json().catch(() => ({}));
    const estado = body.estado === "hecha" ? "hecha" : "error";
    const resultado = String(body.resultado ?? "").slice(0, MAX_RESULTADO);
    const r = await db
      .prepare("UPDATE tareas SET estado = ?, resultado = ?, actualizado = ? WHERE id = ? AND equipo = ? AND estado = 'en_curso'")
      .bind(estado, resultado, Date.now(), body.id, e.nombre)
      .run();
    return r.meta.changes ? json({ ok: true }) : error(404, "tarea no encontrada o ya cerrada");
  }
  return error(404, "ruta desconocida");
}

export default {
  async fetch(request, env) {
    const ruta = new URL(request.url).pathname.split("/").filter(Boolean).map(decodeURIComponent);
    try {
      if (ruta[0] === "admin") return await admin(request, env, ruta);
      if (ruta[0] === "agente") return await agente(request, env, ruta);
      if (ruta.length === 0) return new Response("claude-remoto\n");
      return error(404, "ruta desconocida");
    } catch (err) {
      console.error(err);
      return error(500, "error interno");
    }
  },

  async scheduled(_evento, env) {
    await env.DB.prepare("DELETE FROM tareas WHERE actualizado < ?").bind(Date.now() - RETENCION_MS).run();
  },
};

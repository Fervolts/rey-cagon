// Notificaciones push (FCM HTTP v1). La llaman, con el header x-webhook-secret:
//   - trigger cagadas_avisar: cagada nueva → aviso a los seguidores de quien cagó.
//   - trigger follows_avisar: { tipo: "follow" } → aviso al seguido.
//   - scripts/publicar.sh:   { tipo: "version" } → aviso de versión nueva.
//   - a mano: { tipo: "actualizar_play", build } → a los de Play con un build menor.
//   - trigger cagadas_calificar: { tipo: "placer" } → aviso del secreto, solo a seguidores
//     que también lo desbloquearon y solo para las cagadas que valen la pena contar.
//   - trigger mensajes_avisar_soporte: { tipo: "soporte" } → mensaje de soporte al otro lado del hilo.
//   - trigger mensaje_reportes_contar: { tipo: "reporte_chat" } → aviso a los admins.
//   - trigger mensajes_avisar_mencion: { tipo: "mencion" } → aviso a quien mencionaron con @.
//   - trigger mensajes_avisar_respuesta: { tipo: "respuesta" } → respuesta en un hilo de una sala pública.
//   - retos (Cagadón): { tipo: "reto", evento } → nuevo, aceptado, rechazado o fin del día.
//   - trigger anuncios_avisar: { tipo: "anuncio" } → anuncio de un admin a todos los teléfonos.
//   - cron push_poceta: { tipo: "poceta", lista } → empujones del Imperio.
//   - cron push_racha: { tipo: "racha", lista: [{ user_id, llevas, dia }] } → racha del Imperio a punto de perderse.
//   - cron push_ganadores: { tipo: "ganadores", periodo, lista } → quién ganó la semana/mes/año entre tus amigos.
//   - cron push_cierres: { tipo: "cierre", periodo, lista } → la semana/mes/año se acaba: tu puesto y a quién pasar.
//   - imperio_regalar: { tipo: "regalo", id } → un amigo te mandó un Rollo de papel de regalo (categoría imperio).
//   - cron cloaca_semana (cloaca_cerrar_semana, si el flag cloaca_push está prendido): { tipo: "cloaca", semana }
//     → a los premiados de la Cloaca que ganó la liga de esa semana (categoría ganadores).
// Cada quien apaga categorías en push_ajustes (cagadas, rachas, ganadores, cierres, chat, retos,
// seguidores, imperio). Apagar solo quita el push: lo que se guardaba en el centro de avisos se sigue guardando.
// Anuncio, versión y soporte no se apagan.
// Topes (migración avisos_menos, función push_tope): 'cagada' y 'placer' comparten uno por persona cada
// push_config.cagadas_cada_min (90); lo que cae dentro no sale y el siguiente aviso de cagada lo resume
// ("y 3 amigos más desde tu último aviso"). 'version': uno por persona cada push_config.version_cada_horas (20).
// RAMPAGE/HEXAKILL no se frenan pero cuentan como último aviso. Sin la migración no hay tope.
// Lo que va a una persona también se guarda en public.notificaciones (centro de avisos de la app).
// Cada texto va en español y en inglés: cada teléfono recibe el de su idioma (push_tokens.idioma).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT")!);
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

// Inicio del día en Venezuela (UTC-4 fijo), igual que leaderboard().
function inicioDelDia(): string {
  const offset = 4 * 3600_000;
  const local = new Date(Date.now() - offset);
  local.setUTCHours(0, 0, 0, 0);
  return new Date(local.getTime() + offset).toISOString();
}

const b64url = (data: ArrayBuffer | string) =>
  btoa(typeof data === "string" ? data : String.fromCharCode(...new Uint8Array(data)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

let cache: { token: string; exp: number } | null = null;

// Token OAuth2 de la cuenta de servicio (JWT RS256 firmado con Web Crypto).
async function accessToken(): Promise<string> {
  if (cache && cache.exp > Date.now() + 60_000) return cache.token;
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const firma = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${b64url(firma)}`,
    }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`OAuth: ${JSON.stringify(json)}`);
  cache = { token: json.access_token, exp: Date.now() + json.expires_in * 1000 };
  return cache.token;
}

// Título y cuerpo en los dos idiomas.
type Aviso = { es: [string, string]; en: [string, string] };
const aviso = (esTitulo: string, esCuerpo: string, enTitulo: string, enCuerpo: string): Aviso =>
  ({ es: [esTitulo, esCuerpo], en: [enTitulo, enCuerpo] });
const enSuIdioma = (a: Aviso, idioma?: string | null) => (idioma === "en" ? a.en : a.es);

async function enviar(token: string, title: string, body: string, data: Record<string, string> = {}) {
  const bearer = await accessToken();
  return fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: { token, notification: { title, body }, data, android: { notification: { channel_id: "cagadas" } } },
    }),
  });
}

// Un teléfono a avisar y lo que le toca.
type Destino = { token: string; user_id?: string | null; idioma?: string | null };
type Mensaje = { titulo: string; cuerpo: string; data: Record<string, string>; subtipo?: string; variante?: string };

// Manda un push a cada destino, registra cada envío en push_envios (su id va en data.envio),
// borra los tokens muertos y marca ok = false lo que FCM rechazó. Si push_envios no existe
// todavía (migración sin aplicar) manda igual, sin envio.
async function repartir(tipo: string, destinos: Destino[], armar: (d: Destino) => Mensaje) {
  const lista = destinos.map((d) => ({ d, m: armar(d), envio: null as number | null }));
  const registrables = lista.filter((x) => x.d.user_id);
  for (let i = 0; i < registrables.length; i += 500) {
    const tanda = registrables.slice(i, i + 500);
    const { data: filas, error } = await db.from("push_envios").insert(tanda.map((x) => ({
      user_id: x.d.user_id,
      tipo,
      subtipo: x.m.subtipo ?? null,
      variante: x.m.variante ?? null,
    }))).select("id");
    if (error) {
      console.error("push_envios", error.message);
      break;
    }
    // Los ids salen de una identidad: en orden ascendente quedan en el orden de la tanda.
    const ids = (filas ?? []).map((f) => Number(f.id)).sort((a, b) => a - b);
    if (ids.length === tanda.length) tanda.forEach((x, j) => (x.envio = ids[j]));
  }
  const muertos: string[] = [];
  const fallidos: number[] = [];
  if (lista.length) await accessToken(); // calienta la caché antes de mandar en paralelo
  await Promise.all(lista.map(async (x) => {
    const data = x.envio == null ? x.m.data : { ...x.m.data, envio: String(x.envio) };
    const res = await enviar(x.d.token, x.m.titulo, x.m.cuerpo, data);
    if (!res.ok) {
      if (x.envio != null) fallidos.push(x.envio);
      const err = await res.text();
      // Token de una app desinstalada: se borra.
      if (res.status === 404 || err.includes("UNREGISTERED")) muertos.push(x.d.token);
      else console.error("FCM", res.status, err);
    }
  }));
  if (muertos.length) await db.from("push_tokens").delete().in("token", muertos);
  for (let i = 0; i < fallidos.length; i += 500) {
    await db.from("push_envios").update({ ok: false }).in("id", fallidos.slice(i, i + 500));
  }
  return { enviados: lista.length - muertos.length, borrados: muertos.length };
}

// Mismo aviso para todos, cada uno en su idioma.
const fijo = (a: Aviso, data: Record<string, string>) => (d: Destino): Mensaje => {
  const [titulo, cuerpo] = enSuIdioma(a, d.idioma);
  return { titulo, cuerpo, data };
};

// Interruptores de push_ajustes de esos usuarios. Sin fila = todo prendido. Si la consulta falla
// (migración sin aplicar) devuelve vacío y se manda igual.
async function ajustes(usuarios: (string | null | undefined)[], claves: string[]) {
  const mapa = new Map<string, Record<string, unknown>>();
  const unicos = [...new Set(usuarios.filter((u): u is string => !!u))];
  for (let i = 0; i < unicos.length; i += 200) {
    const { data, error } = await db.from("push_ajustes").select(["user_id", ...claves].join(", ")).in("user_id", unicos.slice(i, i + 200));
    if (error) {
      console.error("push_ajustes", error.message);
      return mapa;
    }
    for (const f of (data ?? []) as unknown as Record<string, unknown>[]) mapa.set(String(f.user_id), f);
  }
  return mapa;
}
const prendido = (mapa: Map<string, Record<string, unknown>>, u: string | null | undefined, clave: string) =>
  !u || mapa.get(u)?.[clave] !== false;

// Solo los teléfonos de quienes tienen prendidas todas esas categorías.
async function conAviso(destinos: Destino[], ...claves: string[]) {
  if (!destinos.length) return destinos;
  const mapa = await ajustes(destinos.map((d) => d.user_id), claves);
  return destinos.filter((d) => claves.every((c) => prendido(mapa, d.user_id, c)));
}

// Quién está frenado por el tope de su tipo ('cagadas' = cagada + placer, 'version') y cuántos amigos cagaron desde
// su último aviso (sin contar a autor). Usuario sin entrada = sin tope. Si push_tope no existe todavía, sin tope.
type Tope = { frenado: boolean; otros: number };
async function topes(usuarios: (string | null | undefined)[], tipo: "cagadas" | "version", autor?: string) {
  const mapa = new Map<string, Tope>();
  const ids = [...new Set(usuarios.filter((u): u is string => !!u))];
  if (!ids.length) return mapa;
  const { data, error } = await db.rpc("push_tope", { p_usuarios: ids, p_tipo: tipo, p_autor: autor ?? null });
  if (error) {
    console.error("push_tope", error.message);
    return mapa;
  }
  for (const f of data ?? []) mapa.set(f.user_id, { frenado: !!f.frenado, otros: Number(f.otros) || 0 });
  return mapa;
}
const frenado = (mapa: Map<string, Tope>, u: string | null | undefined) => !!u && !!mapa.get(u)?.frenado;

// Copia del aviso en el centro de avisos de cada usuario, tenga o no teléfono registrado.
async function guardar(usuarios: string[], a: Aviso, datos: Record<string, string>) {
  if (!usuarios.length) return;
  const { error } = await db.from("notificaciones").insert(
    [...new Set(usuarios)].map((u) => ({
      user_id: u,
      tipo: datos.tipo ?? "otro",
      titulo: a.es[0],
      cuerpo: a.es[1],
      titulo_en: a.en[0],
      cuerpo_en: a.en[1],
      datos,
    })),
  );
  if (error) console.error("notificaciones", error.message);
}

// Aviso de nuevo seguidor a todos los teléfonos del seguido.
async function avisarFollow(follower: string, followed: string) {
  const [{ data: perfil }, { data: tokens }, { data: devuelta }] = await Promise.all([
    db.from("profiles").select("username").eq("id", follower).single(),
    db.from("push_tokens").select("token, user_id, idioma").eq("user_id", followed),
    db.from("follows").select("follower").eq("follower", followed).eq("followed", follower).maybeSingle(),
  ]);
  if (!perfil) return Response.json({ enviados: 0 });
  const a = devuelta
    ? aviso(`👀 ${perfil.username} te empezó a seguir`, "Ya lo sigues. Que empiece la guerra 💩",
      `👀 ${perfil.username} started following you`, "You already follow them. Let the war begin 💩")
    : aviso(`👀 ${perfil.username} te empezó a seguir`, "Síguelo de vuelta para saber cuánto caga 💩",
      `👀 ${perfil.username} started following you`, "Follow back to see how much they poop 💩");
  const datos = { tipo: "follow", user_id: follower };
  await guardar([followed], a, datos);
  const destinos = await conAviso(tokens ?? [], "seguidores");
  if (!destinos.length) return Response.json({ enviados: 0 });
  const { enviados } = await repartir("follow", destinos, fijo(a, datos));
  return Response.json({ enviados });
}

// Aviso de versión nueva a los teléfonos con un build menor. app_build lo reporta la app
// desde la 1.8.2; las versiones anteriores (null) no saben actualizarse y se omiten.
async function avisarVersion(version: string, build: number) {
  // Los de Play se actualizan por la tienda: solo avisa a la APK directa (null = versión vieja sin canal).
  const { data: tokens } = await db.from("push_tokens").select("token, user_id, idioma").lt("app_build", build)
    .or("canal.is.null,canal.eq.directo");
  if (!tokens?.length) return Response.json({ enviados: 0 });
  // Uno por persona cada push_config.version_cada_horas: al que ya le llegó uno hace poco no se le repite.
  const tope = await topes(tokens.map((t) => t.user_id), "version");
  const destinos = tokens.filter((t) => !frenado(tope, t.user_id));
  if (!destinos.length) return Response.json({ enviados: 0 });
  const a = aviso(
    "Actualízame, mojón 💩",
    `La versión ${version} ya está lista. Toca para instalarla.`,
    "Update me, you turd 💩",
    `Version ${version} is ready. Tap to install it.`,
  );
  const { enviados } = await repartir("version", destinos, fijo(a, { tipo: "version", version }));
  return Response.json({ enviados });
}

// Aviso a mano para los de Play con un build menor (la tienda no siempre insiste): al tocarlo se abre la app,
// que ofrece la actualización de Play. null = teléfono que no reportó canal.
async function avisarActualizarPlay(build: number) {
  const { data: tokens } = await db.from("push_tokens").select("token, user_id, idioma").lt("app_build", build)
    .or("canal.is.null,canal.eq.play");
  if (!tokens?.length) return Response.json({ enviados: 0 });
  const a = aviso(
    "Tu Rey Cagón está viejo 💩",
    "Hay versión nueva en Play con alquileres y temporadas en el Imperio. Toca y actualiza para no quedarte atrás.",
    "Your King of the Throne is outdated 💩",
    "A new version is on Play with rentals and seasons in the Empire. Tap and update so you don't fall behind.",
  );
  const { enviados } = await repartir("version", tokens, fijo(a, { tipo: "version", version: "play" }));
  return Response.json({ enviados });
}

const malas = ["dolorosa", "sangrante", "ardiente"];
const buenas = ["virtuosa", "placentera", "liberadora"];

// Texto del aviso según cómo le fue. null = nada que contar (las del medio no avisan).
function chisme(u: string, placer: number | null, etiquetas: string[]): Aviso | null {
  const todas = (l: string[]) => l.every((e) => etiquetas.includes(e));
  if (placer === 7 && todas(buenas)) {
    return aviso(`👑 ${u} tiró la cagada PERFECTA`, "7 de 7, virtuosa, placentera y liberadora. Brilla como el oro.",
      `👑 ${u} dropped the PERFECT poop`, "7 out of 7, virtuous, pleasurable and liberating. Shining like gold.");
  }
  if (todas(malas)) {
    return aviso(`😈 ${u} invocó al demonio`, "Dolorosa, sangrante y ardiente. Mándale fuerzas (y una vela).",
      `😈 ${u} summoned the devil`, "Painful, bloody and burning. Send strength (and a candle).");
  }
  if (placer === 1) {
    return aviso(`💀 ${u} quedó carbonizado`, "Cagada destructiva, 1 de 7. Que alguien le lleve agua.",
      `💀 ${u} got incinerated`, "Destructive poop, 1 out of 7. Someone bring them water.");
  }
  if (placer === 7) {
    return aviso(`😇 ${u} tocó el cielo`, "Cagada celestial, 7 de 7. Hay gente con suerte.",
      `😇 ${u} touched heaven`, "Heavenly poop, 7 out of 7. Some people have all the luck.");
  }
  if (todas(buenas)) {
    return aviso(`✨ ${u} brilla como el oro`, "Virtuosa, placentera y liberadora. Qué envidia.",
      `✨ ${u} is shining like gold`, "Virtuous, pleasurable and liberating. So jealous.");
  }
  if (etiquetas.includes("sangrante")) {
    return aviso(`🩸 ${u} sangró en el intento`, "Fue una cagada sangrante. Si sigue así, que vaya al médico.",
      `🩸 ${u} bled trying`, "It was a bloody one. If it keeps up, see a doctor.");
  }
  if (etiquetas.includes("ardiente")) {
    return aviso(`🔥 ${u} tiene el ano en llamas`, "Cagada ardiente. Nada de picante por hoy.",
      `🔥 ${u}'s butt is on fire`, "Burning poop. No spicy food today.");
  }
  if (etiquetas.includes("liberadora")) {
    return aviso(`🕊️ ${u} se liberó`, "Cagada liberadora. Salió flotando del baño.",
      `🕊️ ${u} is free`, "Liberating poop. Floated right out of the bathroom.");
  }
  return null;
}

// Aviso del secreto a los seguidores que ya encontraron el easter egg.
async function avisarPlacer(id: string) {
  const { data: c } = await db.from("cagadas").select("user_id, placer, etiquetas").eq("id", id).single();
  if (!c) return Response.json({ enviados: 0 });
  const { data: perfil } = await db.from("profiles").select("username").eq("id", c.user_id).single();
  const texto = perfil && chisme(perfil.username, c.placer, c.etiquetas ?? []);
  if (!texto) return Response.json({ enviados: 0 });
  const { data: seguidores } = await db.from("follows").select("follower").eq("followed", c.user_id);
  const { data: abiertos } = await db.from("profiles").select("id").eq("placer_desbloqueado", true)
    .in("id", (seguidores ?? []).map((s) => s.follower));
  if (!abiertos?.length) return Response.json({ enviados: 0 });
  await guardar(abiertos.map((a) => a.id), texto, { tipo: "placer", user_id: c.user_id });
  const { data: tokens } = await db.from("push_tokens").select("token, user_id, idioma").in("user_id", abiertos.map((a) => a.id));
  const conCagadas = await conAviso(tokens ?? [], "cagadas");
  // Comparte el tope de las cagadas: si ya le llegó un aviso de cagada hace poco, este no sale (queda en el centro).
  const tope = await topes(conCagadas.map((t) => t.user_id), "cagadas");
  const destinos = conCagadas.filter((t) => !frenado(tope, t.user_id));
  if (!destinos.length) return Response.json({ enviados: 0 });
  const { enviados } = await repartir("placer", destinos, fijo(texto, { tipo: "placer", user_id: c.user_id }));
  return Response.json({ enviados });
}

// Manda el mismo aviso a todos los teléfonos de esos usuarios y limpia los tokens muertos.
// clave = categoría de push_ajustes que lo apaga (sin clave no se apaga).
async function avisarA(usuarios: string[], a: Aviso, data: Record<string, string>, clave?: string) {
  if (!usuarios.length) return Response.json({ enviados: 0 });
  await guardar(usuarios, a, data);
  const { data: tokens } = await db.from("push_tokens").select("token, user_id, idioma").in("user_id", usuarios);
  const destinos = clave ? await conAviso(tokens ?? [], clave) : tokens ?? [];
  if (!destinos.length) return Response.json({ enviados: 0 });
  const { enviados } = await repartir(data.tipo ?? "otro", destinos, fijo(a, data));
  return Response.json({ enviados });
}

const recortar = (t: string, n = 120) => (t.length > n ? `${t.slice(0, n - 1)}…` : t);

// Soporte: si escribe el usuario, avisa a los admins; si responde un admin, avisa al usuario.
async function avisarSoporte(id: number) {
  const { data: m } = await db.from("mensajes").select("hilo, user_id, texto, es_bug").eq("id", id).single();
  if (!m) return Response.json({ enviados: 0 });
  if (m.user_id === m.hilo) {
    const [{ data: admins }, { data: perfil }] = await Promise.all([
      db.from("admins").select("user_id"),
      db.from("profiles").select("username").eq("id", m.hilo).single(),
    ]);
    const quien = perfil?.username ?? "Alguien";
    return avisarA(
      (admins ?? []).map((a) => a.user_id).filter((u) => u !== m.user_id),
      m.es_bug
        ? aviso(`🐞 ${quien} reportó un error`, recortar(m.texto), `🐞 ${quien} reported a bug`, recortar(m.texto))
        : aviso(`💬 ${quien} escribió a soporte`, recortar(m.texto), `💬 ${quien} wrote to support`, recortar(m.texto)),
      { tipo: "soporte", hilo: m.hilo },
    );
  }
  return avisarA([m.hilo], aviso("🛠️ Te respondió soporte", recortar(m.texto), "🛠️ Support replied", recortar(m.texto)), {
    tipo: "soporte",
    hilo: m.hilo,
  });
}

// Respuesta en un hilo: el dueño del mensaje padre lo lee distinto que los demás del hilo.
async function avisarRespuesta(id: number, para: string[]) {
  const { data: m } = await db.from("mensajes").select("user_id, texto, sala, responde_a").eq("id", id).single();
  if (!m?.responde_a) return Response.json({ enviados: 0 });
  const [{ data: perfil }, { data: padre }] = await Promise.all([
    db.from("profiles").select("username").eq("id", m.user_id).single(),
    db.from("mensajes").select("user_id").eq("id", m.responde_a).single(),
  ]);
  const quien = perfil?.username ?? "Alguien";
  const cuerpo = recortar(m.texto || "(tarjeta)");
  const datos = { tipo: "respuesta", id: String(id), sala: m.sala, hilo: String(m.responde_a) };
  const dueno = para.filter((u) => u === padre?.user_id);
  const otros = para.filter((u) => u !== padre?.user_id);
  const [a, b] = await Promise.all([
    avisarA(dueno, aviso(`💬 ${quien} respondió tu mensaje`, cuerpo, `💬 ${quien} replied to your message`, cuerpo), datos, "chat"),
    avisarA(otros, aviso(`💬 ${quien} respondió en un hilo`, cuerpo, `💬 ${quien} replied in a thread`, cuerpo), datos, "chat"),
  ]);
  const enviados = ((await a.json()).enviados ?? 0) + ((await b.json()).enviados ?? 0);
  return Response.json({ enviados });
}

// Mensaje reportado en La Letrina: aviso a los admins.
async function avisarReporteChat(mensajeId: number, motivo: string) {
  const [{ data: admins }, { data: m }] = await Promise.all([
    db.from("admins").select("user_id"),
    db.from("mensajes").select("texto, oculto, sala").eq("id", mensajeId).single(),
  ]);
  if (!m) return Response.json({ enviados: 0 });
  const cuerpo = `${motivo}: ${recortar(m.texto || "(tarjeta)", 90)}`;
  return avisarA(
    (admins ?? []).map((a) => a.user_id),
    m.oculto
      ? aviso("🚨 Mensaje ocultado por reportes", cuerpo, "🚨 Message hidden by reports", cuerpo)
      : aviso("🚩 Reportaron un mensaje", cuerpo, "🚩 A message was reported", cuerpo),
    { tipo: "reporte_chat", sala: m.sala },
  );
}

// "@username" en una sala pública: aviso a los mencionados (el toque abre esa sala).
async function avisarMencion(id: number, para: string[]) {
  const { data: m } = await db.from("mensajes").select("user_id, texto, sala").eq("id", id).single();
  if (!m) return Response.json({ enviados: 0 });
  const { data: perfil } = await db.from("profiles").select("username").eq("id", m.user_id).single();
  const quien = perfil?.username ?? "Alguien";
  return avisarA(para, aviso(`📣 ${quien} te mencionó`, recortar(m.texto), `📣 ${quien} mentioned you`, recortar(m.texto)), {
    tipo: "mencion",
    id: String(id),
    sala: m.sala,
  }, "chat");
}

// El Cagadón: avisos del reto a quien le toca.
async function avisarReto(id: number, evento: string) {
  const { data: r } = await db.from("retos")
    .select("retador, retado, ganador, marcador_retador, marcador_retado").eq("id", id).single();
  if (!r) return Response.json({ enviados: 0 });
  const { data: perfiles } = await db.from("profiles").select("id, username, genero").in("id", [r.retador, r.retado]);
  const nombre = (u: string) => perfiles?.find((p) => p.id === u)?.username ?? "Alguien";
  const data = { tipo: "reto", id: String(id) };
  if (evento === "nuevo") {
    return avisarA([r.retado], aviso(
      `⚔️ ${nombre(r.retador)} te retó a un Cagadón`, "Gana el que cague más hoy. ¿Aceptas o te rajas?",
      `⚔️ ${nombre(r.retador)} challenged you to a Poop-Off`, "Whoever poops the most today wins. In or chicken?",
    ), data, "retos");
  }
  if (evento === "aceptado") {
    return avisarA([r.retador], aviso(
      `🔥 ${nombre(r.retado)} aceptó tu Cagadón`, "Que empiece la guerra. Gana el que cague más hoy 💩",
      `🔥 ${nombre(r.retado)} accepted your Poop-Off`, "Let the war begin. Whoever poops the most today wins 💩",
    ), data, "retos");
  }
  if (evento === "rechazado") {
    return avisarA([r.retador], aviso(
      `🐔 ${nombre(r.retado)} se rajó`, "No aceptó tu Cagadón. Cobarde.",
      `🐔 ${nombre(r.retado)} chickened out`, "They turned down your Poop-Off. Coward.",
    ), data, "retos");
  }
  const marcador = (yo: string) =>
    yo === r.retador ? `${r.marcador_retador}-${r.marcador_retado}` : `${r.marcador_retado}-${r.marcador_retador}`;
  if (!r.ganador) {
    return avisarA([r.retador, r.retado], aviso(
      "🤝 Cagadón empatado en cero", "Ninguno cagó. Qué decepción.",
      "🤝 Poop-Off tied at zero", "Nobody pooped. What a letdown.",
    ), data, "retos");
  }
  const perdedor = r.ganador === r.retador ? r.retado : r.retador;
  const reina = perfiles?.find((p) => p.id === r.ganador)?.genero === "mujer";
  await avisarA([r.ganador], aviso(
    "🏆 ¡Ganaste el Cagadón!", `${marcador(r.ganador)} contra ${nombre(perdedor)}. ${reina ? "Reina indiscutible" : "Rey indiscutible"} 👑`,
    "🏆 You won the Poop-Off!", `${marcador(r.ganador)} against ${nombre(perdedor)}. Undisputed ${reina ? "queen" : "king"} 👑`,
  ), data, "retos");
  return avisarA([perdedor], aviso(
    "💀 Perdiste el Cagadón", `${marcador(perdedor)} contra ${nombre(r.ganador)}. Mañana revancha.`,
    "💀 You lost the Poop-Off", `${marcador(perdedor)} against ${nombre(r.ganador)}. Rematch tomorrow.`,
  ), data, "retos");
}

// Regalo del Imperio: aviso al que lo recibe. El toque abre el Imperio, donde se abre el regalo.
async function avisarRegalo(id: string) {
  const { data: g } = await db.from("imperio_regalos").select("de, para, abierto").eq("id", id).maybeSingle();
  if (!g || g.abierto) return Response.json({ enviados: 0 });
  const { data: perfil } = await db.from("profiles").select("username").eq("id", g.de).maybeSingle();
  const quien = perfil?.username ?? "Alguien";
  return avisarA([g.para], aviso(
    `🎁 ${quien} te mandó un rollo de regalo`, "Ábrelo en tu Imperio y cobra producción gratis 🧻",
    `🎁 ${quien} sent you a gift roll`, "Open it in your Empire for free production 🧻",
  ), { tipo: "regalo", id: String(id) }, "imperio");
}

// Liga de Cloacas: la Cloaca ganadora de la semana. Solo a los que ganaron premio (miembros con puntos).
async function avisarCloaca(semana: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(semana ?? "")) return Response.json({ enviados: 0 });
  const { data: h } = await db.from("cloaca_historial").select("nombre, emoji").eq("semana", semana).eq("puesto", 1).maybeSingle();
  if (!h) return Response.json({ enviados: 0 });
  const { data: premios } = await db.from("cloaca_premios").select("user_id, rollos").eq("semana", semana);
  const usuarios = (premios ?? []).map((p) => p.user_id as string);
  const rollos = premios?.[0]?.rollos ?? 0;
  return avisarA(usuarios, aviso(
    `🏆 ${h.emoji} ${h.nombre} ganó la liga de Cloacas`, `Entra a Cloacas y cobra tus ${rollos} Rollos de Oro 🧻`,
    `🏆 ${h.emoji} ${h.nombre} won the Sewer league`, `Open Sewers and claim your ${rollos} Golden Rolls 🧻`,
  ), { tipo: "cloaca", semana }, "ganadores");
}

// Anuncio de un admin: a todos los teléfonos (o solo a los de un idioma), de Play y de la APK
// directa. No se guarda por usuario: la app lee public.anuncios directo.
async function avisarAnuncio(id: number) {
  const { data: a } = await db.from("anuncios").select("titulo, texto, emoji, idioma").eq("id", id).single();
  if (!a) return Response.json({ enviados: 0 });
  const consulta = db.from("push_tokens").select("token, user_id");
  const { data: tokens } = await (a.idioma ? consulta.eq("idioma", a.idioma) : consulta);
  if (!tokens?.length) return Response.json({ enviados: 0 });
  const mensaje = { titulo: `${a.emoji ?? "📢"} ${a.titulo}`, cuerpo: recortar(a.texto, 160), data: { tipo: "anuncio", id: String(id) } };
  const { enviados } = await repartir("anuncio", tokens, () => mensaje);
  return Response.json({ enviados });
}

// ---- Poceta (Imperio) ----

// Copia de formatoMj (lib/imperio/formato.dart): "12,5", "999", "1,23 M", "15 K", "1,23e21".
const sufijos = ["K", "M", "B", "T", "Qa", "Qi"];
const sinCeros = (s: string) => (s.includes(".") ? s.replace(/0+$/, "").replace(/\.$/, "") : s);
function formatoMj(v: number, ingles = false): string {
  const fin = (s: string) => (ingles ? s : s.replaceAll(".", ","));
  if (Number.isNaN(v)) return "0";
  if (!Number.isFinite(v)) return v < 0 ? "-∞" : "∞";
  if (v < 1000) {
    if (v < 100) return fin(sinCeros(v.toFixed(1)));
    return String(Math.round(v));
  }
  let exp = 0;
  let x = v;
  while (x >= 1000 && exp < sufijos.length) {
    x /= 1000;
    exp++;
  }
  if (x >= 1000) {
    const [mant, e] = v.toExponential(2).split("e");
    return fin(`${sinCeros(mant)}e${parseInt(e, 10)}`);
  }
  let t = sinCeros(x.toFixed(2));
  if (t === "1000" && exp < sufijos.length) {
    t = "1";
    exp++;
  }
  return fin(`${t} ${sufijos[exp - 1]}`);
}

// "30 h" o "3 días".
const tiempo = (h: number, en: boolean) =>
  h >= 48 ? `${Math.floor(h / 24)} ${en ? "days" : "días"}` : `${h} h`;

type Poceta = { user_id: string; subtipo: string; mj?: number; horas?: number; faltan?: number; pagable?: boolean };

// Variantes A/B/C por subtipo. Cada una devuelve el aviso con los números de esa persona.
const textosPoceta: Record<string, ((p: Poceta) => Aviso)[]> = {
  ganancia: [
    (p) => aviso(`💸 Tu poceta hizo ${formatoMj(p.mj ?? 0)} mojonólares`, "Siguió produciendo mientras no estabas. Ven a cobrar 🚽",
      `💸 Your toilet made ${formatoMj(p.mj ?? 0, true)} Poopbucks`, "It kept producing while you were away. Come collect 🚽"),
    (p) => aviso("🚽 La poceta no descansa", `Te juntó ${formatoMj(p.mj ?? 0)} mojonólares. Están calienticos 💩`,
      "🚽 The toilet never rests", `It piled up ${formatoMj(p.mj ?? 0, true)} Poopbucks for you. Still warm 💩`),
    (p) => aviso(`💰 ${formatoMj(p.mj ?? 0)} mojonólares te esperan`, "Tu imperio sigue cagando plata. Ven antes de que se tapen las tuberías 🪠",
      `💰 ${formatoMj(p.mj ?? 0, true)} Poopbucks are waiting`, "Your empire keeps pooping money. Come before the pipes clog 🪠"),
  ],
  extrana: [
    (p) => aviso("Tu poceta te extraña 🚽🥺", `Hace ${tiempo(p.horas ?? 24, false)} que no te sientas en ella. Está fría y sola.`,
      "Your toilet misses you 🚽🥺", `You haven't sat on it in ${tiempo(p.horas ?? 24, true)}. It's cold and lonely.`),
    (_) => aviso("🥺 La poceta pregunta por ti", "Dice que ya no la quieres. Demuéstrale lo contrario.",
      "🥺 The toilet asked about you", "It thinks you don't love it anymore. Prove it wrong."),
    (_) => aviso("🚽 ¿Y tu imperio?", "Tus empleados de la poceta están de brazos cruzados. Ven a ponerlos a pujar 💩",
      "🚽 What about your empire?", "Your toilet crew is just sitting around. Come make them push 💩"),
  ],
  regalo: [
    (p) => aviso("🎁 Te guardamos un regalo", `Llevas ${tiempo(p.horas ?? 48, false)} sin entrar. Vuelve y cobra 4 h de producción gratis 🚽`,
      "🎁 We saved you a gift", `You've been away ${tiempo(p.horas ?? 48, true)}. Come back and collect 4 h of free production 🚽`),
    (_) => aviso("🎁 Regalo de vuelta", "Tu poceta te tiene 4 h de producción de regalo. Solo tienes que entrar.",
      "🎁 Welcome back gift", "Your toilet has 4 h of production waiting for you. Just open the app."),
    (_) => aviso("🚽 Tu trono te espera con regalo", "Entra hoy y te llevas 4 h de producción gratis 💩",
      "🚽 Your throne has a gift", "Come in today and get 4 h of free production 💩"),
  ],
  empujon: [
    (_) => aviso("💪 Te quedaste un poquito atrás", "Te regalamos producción x2 por 30 min. Entra y alcanza a los demás 🚽",
      "💪 You fell a little behind", "Here's x2 production for 30 min. Come in and catch up 🚽"),
    (_) => aviso("🚀 Un empujón para ti", "Producción x2 por 30 min apenas entres. Dale gas a tu imperio 💨",
      "🚀 A boost for you", "x2 production for 30 min as soon as you open. Floor it 💨"),
    (_) => aviso("🎁 Empujoncito de regalo", "x2 de producción por 30 min, solo por entrar hoy 💩",
      "🎁 A little boost", "x2 production for 30 min, just for coming in today 💩"),
  ],
  candado: [
    (p) => aviso(`🔒 Te ${(p.faltan ?? 1) === 1 ? "falta" : "faltan"} ${cagadasEs(p.faltan ?? 1)}`,
      p.pagable ? "Para abrir el próximo cagador. O págalas con mojonólares 💸" : "Para abrir el próximo cagador. Al trono 👑",
      `🔒 ${cagadasEn(p.faltan ?? 1)} to go`,
      p.pagable ? "To unlock the next pooper. Or pay for them with Poopbucks 💸" : "To unlock the next pooper. To the throne 👑"),
    (p) => aviso("🏗️ Casi abres un cagador nuevo", `Solo ${cagadasEs(p.faltan ?? 1)} más${p.pagable ? " (o págalas con mojonólares)" : ""} y es tuyo 🚽`,
      "🏗️ A new pooper is almost yours", `Just ${cagadasEn(p.faltan ?? 1)} more${p.pagable ? " (or pay with Poopbucks)" : ""} and it's yours 🚽`),
    (p) => aviso("🚽 El candado está flojito", `A ${cagadasEs(p.faltan ?? 1)} del próximo cagador. ¿Hoy cae?`,
      "🚽 The lock is loose", `${cagadasEn(p.faltan ?? 1)} away from the next pooper. Today's the day?`),
  ],
  jalar: [
    (_) => aviso("⛓️ Ya puedes jalar la cadena", "Tienes las cagadas. Jálala y gana Rollos de Oro 🧻",
      "⛓️ You can pull the chain", "You have the poops. Pull it and earn Golden Rolls 🧻"),
    (_) => aviso("🚽 La cadena está lista", "Jala y tu imperio arranca otra vez, pero más fuerte 💩",
      "🚽 The chain is ready", "Pull it and your empire starts over, but stronger 💩"),
    (_) => aviso("⛓️ ¿Qué esperas?", "Ya juntaste las cagadas para jalar la cadena. Dale.",
      "⛓️ What are you waiting for?", "You already have the poops to pull the chain. Go."),
  ],
  fresca: [
    (_) => aviso("💩 Cagada fresca = x2", "Registra tu cagada de hoy y tu imperio produce el doble por 1 h",
      "💩 Fresh poop = x2", "Log today's poop and your empire produces double for 1 h"),
    (_) => aviso("🚽 ¿Ya cagaste hoy?", "Anótala y te damos x2 de producción por 1 hora 💸",
      "🚽 Pooped yet today?", "Log it and get x2 production for 1 hour 💸"),
    (_) => aviso("⏰ x2 por 1 hora", "Cada cagada que registras pone tu poceta al doble por 1 h. Al trono 👑",
      "⏰ x2 for 1 hour", "Every poop you log doubles your toilet for 1 h. To the throne 👑"),
  ],
  constipado: [
    (p) => aviso("¿Estás constipado? 💩", `${tiempo(p.horas ?? 10, false)} sin cagar... ¿estítico? Toma agüita y vuelve al trono.`,
      "Are you constipated? 💩", `${tiempo(p.horas ?? 10, true)} without pooping... backed up? Drink some water and get back on the throne.`),
    (p) => aviso("🧐 ¿Todo bien allá abajo?", `Llevas ${tiempo(p.horas ?? 10, false)} sin cagar. El ranking no se defiende solo.`,
      "🧐 Everything OK down there?", `${tiempo(p.horas ?? 10, true)} without a poop. The ranking won't defend itself.`),
    (p) => aviso("🪨 ¿Estítico?", `${tiempo(p.horas ?? 10, false)} de sequía. Una papaya y al trono 👑`,
      "🪨 Backed up?", `${tiempo(p.horas ?? 10, true)} dry spell. Eat a prune and hit the throne 👑`),
  ],
};
const letras = ["a", "b", "c"];

// Lista que arma push_poceta_revisar(): un aviso por persona, variante al azar (la misma en
// todos sus teléfonos). No se guarda en notificaciones: es un empujón, no un aviso para leer.
async function avisarPoceta(lista: Poceta[]) {
  const validos = lista.filter((p) => p?.user_id && textosPoceta[p.subtipo]);
  if (!validos.length) return Response.json({ enviados: 0 });
  const elegido = new Map<string, { p: Poceta; i: number }>();
  for (const p of validos) elegido.set(p.user_id, { p, i: Math.floor(Math.random() * textosPoceta[p.subtipo].length) });
  const usuarios = [...elegido.keys()];
  const tokens: Destino[] = [];
  for (let i = 0; i < usuarios.length; i += 200) {
    const { data } = await db.from("push_tokens").select("token, user_id, idioma").in("user_id", usuarios.slice(i, i + 200));
    tokens.push(...(data ?? []));
  }
  const destinos = await conAviso(tokens, "imperio", "poceta");
  if (!destinos.length) return Response.json({ enviados: 0 });
  const r = await repartir("poceta", destinos, (t) => {
    const { p, i } = elegido.get(t.user_id ?? "")!;
    const [titulo, cuerpo] = enSuIdioma(textosPoceta[p.subtipo][i](p), t.idioma);
    return { titulo, cuerpo, subtipo: p.subtipo, variante: letras[i], data: { tipo: "poceta", subtipo: p.subtipo, variante: letras[i] } };
  });
  return Response.json(r);
}

// Premio de cada día de la racha del Imperio (copia de premiosRacha en lib/imperio/racha_imperio.dart).
const premiosRacha: [string, string][] = [
  ["⏰ 15 min de producción", "⏰ 15 min of production"],
  ["🧴 Ambientador criollo", "🧴 Homemade air freshener"],
  ["1 🫐 Ciruela", "1 🫐 Plum"],
  ["⏰ 30 min de producción", "⏰ 30 min of production"],
  ["💊 Laxante express", "💊 Express laxative"],
  ["2 🫐 Ciruelas", "2 🫐 Plums"],
  ["🎟️ 1 Ficha + 3 🫐 Ciruelas", "🎟️ 1 Token + 3 🫐 Plums"],
  ["⏰ 45 min de producción", "⏰ 45 min of production"],
  ["🧻 Papel doble hoja", "🧻 Two-ply paper"],
  ["3 🫐 Ciruelas", "3 🫐 Plums"],
  ["⏰ 1 h de producción", "⏰ 1 h of production"],
  ["🤖 Robot destapador", "🤖 Plunger bot"],
  ["4 🫐 Ciruelas", "4 🫐 Plums"],
  ["🎟️ 1 Ficha + 5 🫐 Ciruelas", "🎟️ 1 Token + 5 🫐 Plums"],
  ["⏰ 2 h de producción", "⏰ 2 h of production"],
  ["🧴 2 Ambientadores", "🧴 2 Air fresheners"],
  ["5 🫐 Ciruelas", "5 🫐 Plums"],
  ["💊 2 Laxantes", "💊 2 Laxatives"],
  ["⏰ 3 h de producción", "⏰ 3 h of production"],
  ["6 🫐 Ciruelas", "6 🫐 Plums"],
  ["🎟️ 1 Ficha + 8 🫐 Ciruelas", "🎟️ 1 Token + 8 🫐 Plums"],
  ["⏰ 4 h de producción", "⏰ 4 h of production"],
  ["🧻 Papel doble hoja + 🤖 Robot destapador", "🧻 Two-ply paper + 🤖 Plunger bot"],
  ["8 🫐 Ciruelas", "8 🫐 Plums"],
  ["⏰ 6 h de producción", "⏰ 6 h of production"],
  ["🧴 Ambientador + 💊 Laxante", "🧴 Air freshener + 💊 Laxative"],
  ["10 🫐 Ciruelas", "10 🫐 Plums"],
  ["🎟️ 1 Ficha + 12 🫐 Ciruelas", "🎟️ 1 Token + 12 🫐 Plums"],
  ["⏰ 8 h de producción", "⏰ 8 h of production"],
  ["25 🫐 Ciruelas + un logro 🏆", "25 🫐 Plums + an achievement 🏆"],
];

type Racha = { user_id: string; llevas: number; dia: number; congeladores?: number; momento?: string };

// Días de la racha con premio gordo: el aviso lo grita.
const hitosRacha = new Set([7, 15, 30]);

// Lista que arma push_racha_revisar(). Un aviso por persona; no se guarda en notificaciones.
// momento: aviso (20:00, reclamó ayer y no hoy), ultima (23:00), perdida / congelador (10:00 del día después de fallar).
function textoRacha(r: Racha): [Aviso, string] {
  const { llevas, dia, congeladores } = r;
  const [es, en] = premiosRacha[dia - 1];
  const diasEs = `${llevas} ${llevas === 1 ? "día" : "días"}`;
  const diasEn = `${llevas} ${llevas === 1 ? "day" : "days"}`;
  const hito = hitosRacha.has(dia);
  if (r.momento === "perdida") {
    return [aviso(
      `💔 Se fue tu racha de ${diasEs}`,
      `Ayer no entraste al Imperio y la racha se fue por la poceta 🚽. Hoy arrancas del día 1, pero arrancas 💪`,
      `💔 Your ${diasEn} streak is gone`,
      `You skipped the Empire yesterday and your streak went down the toilet 🚽. Back to day 1 today, but you're back 💪`,
    ), "perdida"];
  }
  if (r.momento === "congelador") {
    return [aviso(
      `🧊 Tu congelador aguantó la racha`,
      `Ayer no entraste, pero tus ${diasEs} siguen congelados. Entra hoy o se derriten 🫠`,
      `🧊 Your freezer saved the streak`,
      `You skipped yesterday, but your ${diasEn} are still frozen. Come in today or they melt 🫠`,
    ), "congelador"];
  }
  if (r.momento === "ultima") {
    return [aviso(
      hito ? `⏰ Última llamada: ${es} se escapa` : `⏰ Última llamada, llevas ${diasEs} 🔥`,
      `Queda menos de una hora para medianoche. Entra al Imperio o la racha se va por la poceta 🚽`,
      hito ? `⏰ Last call: ${en} is slipping away` : `⏰ Last call, ${diasEn} in a row 🔥`,
      `Less than an hour to midnight. Open the Empire or your streak goes down the toilet 🚽`,
    ), `ultima_${dia}`];
  }
  // Con congelador 🧊 la racha no se pierde, pero se le pide que no lo gaste por flojo.
  const conHielo = (congeladores ?? 0) > 0;
  const titulo: [string, string] = hito
    ? [`🏆 Hoy llegas a ${llevas + 1} días`, `🏆 Day ${llevas + 1} is today`]
    : [`Llevas ${diasEs} 🔥`, `${diasEn} in a row 🔥`];
  return [aviso(
    titulo[0],
    hito
      ? `Premio gordo: ${es}. No lo dejes en la poceta, entra antes de medianoche 🚽`
      : conHielo
      ? `Hoy toca ${es}. Tienes 🧊 congelador, pero no lo gastes por flojo: entra antes de medianoche 🚽`
      : `Hoy toca ${es}. Si no entras antes de medianoche, tu racha se va por la poceta 🚽`,
    titulo[1],
    hito
      ? `Big prize: ${en}. Don't flush it, come in before midnight 🚽`
      : conHielo
      ? `Today you get ${en}. You have a 🧊 freezer, but don't waste it being lazy: come in before midnight 🚽`
      : `Today you get ${en}. If you don't come in before midnight, your streak goes down the toilet 🚽`,
  ), `dia_${dia}`];
}

async function avisarRacha(lista: Racha[]) {
  const porUsuario = new Map<string, Racha>();
  for (const r of lista) if (r?.user_id && r.dia >= 1 && r.dia <= premiosRacha.length) porUsuario.set(r.user_id, r);
  if (!porUsuario.size) return Response.json({ enviados: 0 });
  const usuarios = [...porUsuario.keys()];
  const tokens: Destino[] = [];
  for (let i = 0; i < usuarios.length; i += 200) {
    const { data } = await db.from("push_tokens").select("token, user_id, idioma").in("user_id", usuarios.slice(i, i + 200));
    tokens.push(...(data ?? []));
  }
  const destinos = await conAviso(tokens, "imperio", "racha");
  if (!destinos.length) return Response.json({ enviados: 0 });
  const r = await repartir("racha", destinos, (t) => {
    const fila = porUsuario.get(t.user_id ?? "")!;
    const [a, subtipo] = textoRacha(fila);
    const [titulo, cuerpo] = enSuIdioma(a, t.idioma);
    return { titulo, cuerpo, subtipo, data: { tipo: "racha", dia: String(fila.dia), momento: fila.momento ?? "aviso" } };
  });
  return Response.json(r);
}

// ---- Ganadores y cierres (semana / mes / año entre amigos) ----

type Periodo = "week" | "month" | "year";
// [la semana, de la semana, esta semana, week]
const periodos: Record<Periodo, [string, string, string, string]> = {
  week: ["la semana", "de la semana", "Esta semana", "week"],
  month: ["el mes", "del mes", "Este mes", "month"],
  year: ["el año", "del año", "Este año", "year"],
};
const cagadasEs = (n: number) => `${n} ${n === 1 ? "cagada" : "cagadas"}`;
const cagadasEn = (n: number) => `${n} ${n === 1 ? "poop" : "poops"}`;
const ordinalEn = (n: number) =>
  `${n}${n % 100 >= 11 && n % 100 <= 13 ? "th" : n % 10 === 1 ? "st" : n % 10 === 2 ? "nd" : n % 10 === 3 ? "rd" : "th"}`;

// "A", "A y B", "A, B y 3 más".
function quienes(nombres: string[], total: number, en: boolean) {
  const y = en ? "and" : "y";
  if (nombres.length <= 1 && total <= 1) return nombres[0] ?? "?";
  if (total === 2 && nombres.length === 2) return `${nombres[0]} ${y} ${nombres[1]}`;
  const resto = total - 2;
  return resto > 0 ? `${nombres.slice(0, 2).join(", ")} ${y} ${resto} ${en ? "more" : "más"}` : nombres.join(` ${y} `);
}

// Teléfonos de esos usuarios, en tandas.
async function telefonos(usuarios: string[]) {
  const tokens: Destino[] = [];
  for (let i = 0; i < usuarios.length; i += 200) {
    const { data } = await db.from("push_tokens").select("token, user_id, idioma").in("user_id", usuarios.slice(i, i + 200));
    tokens.push(...(data ?? []));
  }
  return tokens;
}

type Ganador = { user_id: string; gane: boolean; n: number; empatados: number; nombres: string[]; reina?: boolean };

function textoGanadores(periodo: Periodo, g: Ganador): Aviso {
  const [la, , esta, en] = periodos[periodo];
  const otros = g.nombres ?? [];
  if (g.gane && g.empatados <= 1) {
    return aviso(`👑 ¡Ganaste ${la}!`, `Nadie entre tus amigos cagó más que tú: ${cagadasEs(g.n)}. ${g.reina ? "Reina" : "Rey"} del trono.`,
      `👑 You won the ${en}!`, `Nobody in your circle pooped more than you: ${cagadasEn(g.n)}. ${g.reina ? "Queen" : "King"} of the throne.`);
  }
  if (g.gane) {
    return aviso(`👑 ¡Empataste en la cima de ${la}!`, `${cagadasEs(g.n)}, igual que ${quienes(otros, g.empatados - 1, false)}. Toca desempatar.`,
      `👑 You tied for the top of the ${en}!`, `${cagadasEn(g.n)}, same as ${quienes(otros, g.empatados - 1, true)}. Time for a tiebreaker.`);
  }
  if (g.empatados <= 1) {
    return aviso(`🏆 ${otros[0]} ganó ${la} entre tus amigos`, `Con ${cagadasEs(g.n)}. ¿${esta} le ganas tú? 💩`,
      `🏆 ${otros[0]} won the ${en} among your friends`, `With ${cagadasEn(g.n)}. Beat them this ${en}? 💩`);
  }
  return aviso(`🏆 Empate en ${la}: ${quienes(otros, g.empatados, false)}`, `${cagadasEs(g.n)} cada uno. ¿${esta} les ganas tú? 💩`,
    `🏆 Tie for the ${en}: ${quienes(otros, g.empatados, true)}`, `${cagadasEn(g.n)} each. Beat them this ${en}? 💩`);
}

// Lista que arma push_ganadores_revisar(): un aviso por persona. Se guarda en el centro de avisos.
async function avisarGanadores(periodo: Periodo, lista: Ganador[]) {
  if (!periodos[periodo]) return Response.json({ enviados: 0 });
  const porUsuario = new Map<string, Aviso>();
  for (const g of lista) {
    if (!g?.user_id || !(g.n > 0) || (!g.gane && !g.nombres?.length)) continue;
    porUsuario.set(g.user_id, textoGanadores(periodo, g));
  }
  if (!porUsuario.size) return Response.json({ enviados: 0 });
  const datos = { tipo: "ganadores", periodo };
  const filas = [...porUsuario].map(([u, a]) => ({
    user_id: u, tipo: "ganadores", titulo: a.es[0], cuerpo: a.es[1], titulo_en: a.en[0], cuerpo_en: a.en[1], datos,
  }));
  for (let i = 0; i < filas.length; i += 500) {
    const { error } = await db.from("notificaciones").insert(filas.slice(i, i + 500));
    if (error) console.error("notificaciones", error.message);
  }
  const destinos = await conAviso(await telefonos([...porUsuario.keys()]), "ganadores");
  if (!destinos.length) return Response.json({ enviados: 0 });
  const r = await repartir("ganadores", destinos, (t) => {
    const [titulo, cuerpo] = enSuIdioma(porUsuario.get(t.user_id ?? "")!, t.idioma);
    return { titulo, cuerpo, subtipo: periodo, data: datos };
  });
  return Response.json(r);
}

type Cierre = { user_id: string; n: number; puesto: number; empatados: number; rival?: string | null; rival_n?: number | null; horas: number };

function textoCierre(periodo: Periodo, c: Cierre): Aviso {
  const [, del, , en] = periodos[periodo];
  const h = Math.max(1, Math.round(c.horas ?? 6));
  const titulo = aviso(`⏳ Quedan ${h} h ${del}`, "", `⏳ ${h} h left in the ${en}`, "");
  const rival = c.rival ?? null;
  const suyas = c.rival_n ?? 0;
  let es: string;
  let ing: string;
  if (c.puesto === 1 && c.empatados > 0 && rival) {
    es = `Vas empatado en el 1º con ${rival} (${cagadasEs(c.n)}). Una más y ganas 👑`;
    ing = `You're tied for 1st with ${rival} (${cagadasEn(c.n)}). One more and you win 👑`;
  } else if (c.puesto === 1) {
    es = rival
      ? `Vas 1º con ${cagadasEs(c.n)}, ${rival} te sigue a ${c.n - suyas}. Aguanta el trono 👑`
      : `Vas 1º con ${cagadasEs(c.n)}. Aguanta el trono 👑`;
    ing = rival
      ? `You're 1st with ${cagadasEn(c.n)}, ${rival} is ${c.n - suyas} behind. Hold the throne 👑`
      : `You're 1st with ${cagadasEn(c.n)}. Hold the throne 👑`;
  } else {
    es = `Vas ${c.puesto}º, a ${cagadasEs(suyas - c.n)} de ${rival ?? "?"}. ¡Puja! 💩`;
    ing = `You're ${ordinalEn(c.puesto)}, ${cagadasEn(suyas - c.n)} behind ${rival ?? "?"}. Push! 💩`;
  }
  return aviso(titulo.es[0], es, titulo.en[0], ing);
}

// Lista que arma push_cierres_revisar(): un aviso por persona. No se guarda: es un empujón.
async function avisarCierre(periodo: Periodo, lista: Cierre[]) {
  if (!periodos[periodo]) return Response.json({ enviados: 0 });
  const porUsuario = new Map<string, Aviso>();
  for (const c of lista) if (c?.user_id && c.puesto >= 1) porUsuario.set(c.user_id, textoCierre(periodo, c));
  if (!porUsuario.size) return Response.json({ enviados: 0 });
  const destinos = await conAviso(await telefonos([...porUsuario.keys()]), "cierres");
  if (!destinos.length) return Response.json({ enviados: 0 });
  const r = await repartir("cierre", destinos, (t) => {
    const [titulo, cuerpo] = enSuIdioma(porUsuario.get(t.user_id ?? "")!, t.idioma);
    return { titulo, cuerpo, subtipo: periodo, data: { tipo: "cierre", periodo } };
  });
  return Response.json(r);
}

Deno.serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== Deno.env.get("WEBHOOK_SECRET")) {
    return new Response("no", { status: 401 });
  }
  const cuerpo = await req.json();
  if (cuerpo.tipo === "follow") return avisarFollow(cuerpo.follower, cuerpo.followed);
  if (cuerpo.tipo === "version") return avisarVersion(cuerpo.version, cuerpo.build);
  if (cuerpo.tipo === "actualizar_play") return avisarActualizarPlay(cuerpo.build);
  if (cuerpo.tipo === "placer") return avisarPlacer(cuerpo.id);
  if (cuerpo.tipo === "soporte") return avisarSoporte(cuerpo.id);
  if (cuerpo.tipo === "mencion") return avisarMencion(cuerpo.id, cuerpo.para);
  if (cuerpo.tipo === "respuesta") return avisarRespuesta(cuerpo.id, cuerpo.para);
  if (cuerpo.tipo === "reto") return avisarReto(cuerpo.id, cuerpo.evento);
  if (cuerpo.tipo === "anuncio") return avisarAnuncio(cuerpo.id);
  if (cuerpo.tipo === "reporte_chat") return avisarReporteChat(cuerpo.mensaje_id, cuerpo.motivo);
  if (cuerpo.tipo === "poceta") return avisarPoceta(cuerpo.lista ?? []);
  if (cuerpo.tipo === "racha") return avisarRacha(cuerpo.lista ?? []);
  if (cuerpo.tipo === "ganadores") return avisarGanadores(cuerpo.periodo, cuerpo.lista ?? []);
  if (cuerpo.tipo === "cierre") return avisarCierre(cuerpo.periodo, cuerpo.lista ?? []);
  if (cuerpo.tipo === "regalo") return avisarRegalo(String(cuerpo.id));
  if (cuerpo.tipo === "cloaca") return avisarCloaca(String(cuerpo.semana));
  const { user_id } = cuerpo;

  const { data: seguidores } = await db.from("follows").select("follower").eq("followed", user_id);
  if (!seguidores?.length) return Response.json({ enviados: 0 });

  const [{ data: perfil }, { data: hoy }, { data: tokens }] = await Promise.all([
    db.from("profiles").select("username").eq("id", user_id).single(),
    db.from("cagadas").select("user_id").gte("created_at", inicioDelDia()),
    db.from("push_tokens").select("token, user_id, idioma").in("user_id", seguidores.map((s) => s.follower)),
  ]);
  if (!perfil || !tokens?.length) return Response.json({ enviados: 0 });

  const cuenta = new Map<string, number>();
  for (const c of hoy ?? []) cuenta.set(c.user_id, (cuenta.get(c.user_id) ?? 0) + 1);
  const n = cuenta.get(user_id) ?? 0;

  // 5ª del día = RAMPAGE, 6ª = HEXAKILL: reemplaza al push de siempre para quien tiene "rachas" prendido y
  // queda en el centro de avisos de todos los seguidores. Con "rachas" apagado llega el de siempre si
  // tiene "cagadas" prendido.
  const especial = n === 5 ? "rampage" : n === 6 ? "hexakill" : null;
  const mapa = await ajustes(tokens.map((t) => t.user_id), ["cagadas", "rachas"]);
  const hype = especial ? tokens.filter((t) => prendido(mapa, t.user_id, "rachas")) : [];
  const candidatos = tokens.filter((t) => !hype.includes(t) && prendido(mapa, t.user_id, "cagadas"));
  // Tope: como mucho un aviso de cagada (o placer) por persona cada push_config.cagadas_cada_min. El que está
  // frenado no recibe push (sí queda en el centro de avisos); el siguiente le cuenta cuántos amigos cagaron mientras.
  const tope = await topes(candidatos.map((t) => t.user_id), "cagadas", user_id);
  const normales = candidatos.filter((t) => !frenado(tope, t.user_id));
  const u = perfil.username;

  let enviados = 0;
  let borrados = 0;
  if (especial) {
    const datosHype = { tipo: "cagada", subtipo: especial, user_id };
    const texto = (mio: number | null): Aviso => {
      const tuEs = mio == null ? "" : ` Tú llevas ${mio}.`;
      const tuEn = mio == null ? "" : ` You're at ${mio}.`;
      return especial === "rampage"
        ? aviso(`🔥 ¡RAMPAGE! ${u} lleva 5 cagadas hoy`, `Cinco en un día. Está imparable.${tuEs}`,
          `🔥 RAMPAGE! ${u} pooped 5 times today`, `Five in one day. Unstoppable.${tuEn}`)
        : aviso(`☠️ ¡HEXAKILL! ${u} cagó 6 veces hoy`, `Seis. SEIS. Que alguien revise esas tuberías.${tuEs}`,
          `☠️ HEXAKILL! ${u} pooped 6 times today`, `Six. SIX. Someone check those pipes.${tuEn}`);
    };
    await guardar(seguidores.map((s) => s.follower), texto(null), datosHype);
    if (hype.length) {
      const r = await repartir("cagada", hype, (t) => {
        const [titulo, cuerpo] = enSuIdioma(texto(cuenta.get(t.user_id ?? "") ?? 0), t.idioma);
        return { titulo, cuerpo, subtipo: especial, data: datosHype };
      });
      enviados += r.enviados;
      borrados += r.borrados;
    }
  }

  const data = { tipo: "cagada", user_id };
  if (normales.length) {
    const r = await repartir("cagada", normales, (t) => {
      const mio = cuenta.get(t.user_id ?? "") ?? 0;
      const en = t.idioma === "en";
      const otros = tope.get(t.user_id ?? "")?.otros ?? 0;
      const resumen = otros <= 0 ? ""
        : en
        ? ` (and ${otros} ${otros === 1 ? "more friend" : "more friends"} since your last alert)`
        : ` (y ${otros} ${otros === 1 ? "amigo más" : "amigos más"} desde tu último aviso)`;
      const cola = en
        ? (mio < n ? "you're losing 😬" : mio === n ? "you're tied 👀" : "you're still winning 👑")
        : (mio < n ? "vas perdiendo 😬" : mio === n ? "van empatados 👀" : "todavía le ganas 👑");
      return en
        ? { titulo: `💩 ${u} pooped${resumen}`, cuerpo: `${u} pooped ${n} ${n === 1 ? "time" : "times"} today... ${cola}`, data }
        : { titulo: `💩 ${u} cagó${resumen}`, cuerpo: `${u} cagó ${n} ${n === 1 ? "vez" : "veces"} hoy... ${cola}`, data };
    });
    enviados += r.enviados;
    borrados += r.borrados;
  }

  return Response.json({ enviados, borrados });
});

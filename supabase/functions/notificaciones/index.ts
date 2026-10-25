// Notificaciones push (FCM HTTP v1). La llaman, con el header x-webhook-secret:
//   - trigger cagadas_avisar: cagada nueva → aviso a los seguidores de quien cagó.
//   - trigger follows_avisar: { tipo: "follow" } → aviso al seguido.
//   - scripts/publicar.sh:   { tipo: "version" } → aviso de versión nueva.
//   - trigger cagadas_calificar: { tipo: "placer" } → aviso del secreto, solo a seguidores
//     que también lo desbloquearon y solo para las cagadas que valen la pena contar.
//   - trigger mensajes_avisar_soporte: { tipo: "soporte" } → mensaje de soporte al otro lado del hilo.
//   - trigger mensaje_reportes_contar: { tipo: "reporte_chat" } → aviso a los admins.
//   - trigger mensajes_avisar_mencion: { tipo: "mencion" } → aviso a quien mencionaron con @.
//   - retos (Cagadón): { tipo: "reto", evento } → nuevo, aceptado, rechazado o fin del día.
//   - trigger anuncios_avisar: { tipo: "anuncio" } → anuncio de un admin a todos los teléfonos.
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
    db.from("push_tokens").select("token, idioma").eq("user_id", followed),
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
  if (!tokens?.length) return Response.json({ enviados: 0 });
  const muertos: string[] = [];
  await Promise.all(tokens.map(async (t) => {
    const res = await enviar(t.token, ...enSuIdioma(a, t.idioma), datos);
    if (!res.ok) {
      const err = await res.text();
      if (res.status === 404 || err.includes("UNREGISTERED")) muertos.push(t.token);
      else console.error("FCM", res.status, err);
    }
  }));
  if (muertos.length) await db.from("push_tokens").delete().in("token", muertos);
  return Response.json({ enviados: tokens.length - muertos.length });
}

// Aviso de versión nueva a los teléfonos con un build menor. app_build lo reporta la app
// desde la 1.8.2; las versiones anteriores (null) no saben actualizarse y se omiten.
async function avisarVersion(version: string, build: number) {
  // Los de Play se actualizan por la tienda: solo avisa a la APK directa (null = versión vieja sin canal).
  const { data: tokens } = await db.from("push_tokens").select("token, idioma").lt("app_build", build)
    .or("canal.is.null,canal.eq.directo");
  if (!tokens?.length) return Response.json({ enviados: 0 });
  const muertos: string[] = [];
  await Promise.all(tokens.map(async (t) => {
    const res = await enviar(
      t.token,
      ...enSuIdioma(aviso(
        "Actualízame, mojón 💩",
        `La versión ${version} ya está lista. Toca para instalarla.`,
        "Update me, you turd 💩",
        `Version ${version} is ready. Tap to install it.`,
      ), t.idioma),
      { tipo: "version", version },
    );
    if (!res.ok) {
      const err = await res.text();
      if (res.status === 404 || err.includes("UNREGISTERED")) muertos.push(t.token);
      else console.error("FCM", res.status, err);
    }
  }));
  if (muertos.length) await db.from("push_tokens").delete().in("token", muertos);
  return Response.json({ enviados: tokens.length - muertos.length });
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
  const { data: tokens } = await db.from("push_tokens").select("token, idioma").in("user_id", abiertos.map((a) => a.id));
  if (!tokens?.length) return Response.json({ enviados: 0 });
  const muertos: string[] = [];
  await Promise.all(tokens.map(async (t) => {
    const res = await enviar(t.token, ...enSuIdioma(texto, t.idioma), { tipo: "placer", user_id: c.user_id });
    if (!res.ok) {
      const err = await res.text();
      if (res.status === 404 || err.includes("UNREGISTERED")) muertos.push(t.token);
      else console.error("FCM", res.status, err);
    }
  }));
  if (muertos.length) await db.from("push_tokens").delete().in("token", muertos);
  return Response.json({ enviados: tokens.length - muertos.length });
}

// Manda el mismo aviso a todos los teléfonos de esos usuarios y limpia los tokens muertos.
async function avisarA(usuarios: string[], a: Aviso, data: Record<string, string>) {
  if (!usuarios.length) return Response.json({ enviados: 0 });
  await guardar(usuarios, a, data);
  const { data: tokens } = await db.from("push_tokens").select("token, idioma").in("user_id", usuarios);
  if (!tokens?.length) return Response.json({ enviados: 0 });
  const muertos: string[] = [];
  await Promise.all(tokens.map(async (t) => {
    const res = await enviar(t.token, ...enSuIdioma(a, t.idioma), data);
    if (!res.ok) {
      const err = await res.text();
      if (res.status === 404 || err.includes("UNREGISTERED")) muertos.push(t.token);
      else console.error("FCM", res.status, err);
    }
  }));
  if (muertos.length) await db.from("push_tokens").delete().in("token", muertos);
  return Response.json({ enviados: tokens.length - muertos.length });
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
  });
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
    ), data);
  }
  if (evento === "aceptado") {
    return avisarA([r.retador], aviso(
      `🔥 ${nombre(r.retado)} aceptó tu Cagadón`, "Que empiece la guerra. Gana el que cague más hoy 💩",
      `🔥 ${nombre(r.retado)} accepted your Poop-Off`, "Let the war begin. Whoever poops the most today wins 💩",
    ), data);
  }
  if (evento === "rechazado") {
    return avisarA([r.retador], aviso(
      `🐔 ${nombre(r.retado)} se rajó`, "No aceptó tu Cagadón. Cobarde.",
      `🐔 ${nombre(r.retado)} chickened out`, "They turned down your Poop-Off. Coward.",
    ), data);
  }
  const marcador = (yo: string) =>
    yo === r.retador ? `${r.marcador_retador}-${r.marcador_retado}` : `${r.marcador_retado}-${r.marcador_retador}`;
  if (!r.ganador) {
    return avisarA([r.retador, r.retado], aviso(
      "🤝 Cagadón empatado en cero", "Ninguno cagó. Qué decepción.",
      "🤝 Poop-Off tied at zero", "Nobody pooped. What a letdown.",
    ), data);
  }
  const perdedor = r.ganador === r.retador ? r.retado : r.retador;
  const reina = perfiles?.find((p) => p.id === r.ganador)?.genero === "mujer";
  await avisarA([r.ganador], aviso(
    "🏆 ¡Ganaste el Cagadón!", `${marcador(r.ganador)} contra ${nombre(perdedor)}. ${reina ? "Reina indiscutible" : "Rey indiscutible"} 👑`,
    "🏆 You won the Poop-Off!", `${marcador(r.ganador)} against ${nombre(perdedor)}. Undisputed ${reina ? "queen" : "king"} 👑`,
  ), data);
  return avisarA([perdedor], aviso(
    "💀 Perdiste el Cagadón", `${marcador(perdedor)} contra ${nombre(r.ganador)}. Mañana revancha.`,
    "💀 You lost the Poop-Off", `${marcador(perdedor)} against ${nombre(r.ganador)}. Rematch tomorrow.`,
  ), data);
}

// Anuncio de un admin: a todos los teléfonos (o solo a los de un idioma), de Play y de la APK
// directa. No se guarda por usuario: la app lee public.anuncios directo.
async function avisarAnuncio(id: number) {
  const { data: a } = await db.from("anuncios").select("titulo, texto, emoji, idioma").eq("id", id).single();
  if (!a) return Response.json({ enviados: 0 });
  const consulta = db.from("push_tokens").select("token");
  const { data: tokens } = await (a.idioma ? consulta.eq("idioma", a.idioma) : consulta);
  if (!tokens?.length) return Response.json({ enviados: 0 });
  const muertos: string[] = [];
  await Promise.all(tokens.map(async (t) => {
    const res = await enviar(t.token, `${a.emoji ?? "📢"} ${a.titulo}`, recortar(a.texto, 160), { tipo: "anuncio", id: String(id) });
    if (!res.ok) {
      const err = await res.text();
      if (res.status === 404 || err.includes("UNREGISTERED")) muertos.push(t.token);
      else console.error("FCM", res.status, err);
    }
  }));
  if (muertos.length) await db.from("push_tokens").delete().in("token", muertos);
  return Response.json({ enviados: tokens.length - muertos.length });
}

Deno.serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== Deno.env.get("WEBHOOK_SECRET")) {
    return new Response("no", { status: 401 });
  }
  const cuerpo = await req.json();
  if (cuerpo.tipo === "follow") return avisarFollow(cuerpo.follower, cuerpo.followed);
  if (cuerpo.tipo === "version") return avisarVersion(cuerpo.version, cuerpo.build);
  if (cuerpo.tipo === "placer") return avisarPlacer(cuerpo.id);
  if (cuerpo.tipo === "soporte") return avisarSoporte(cuerpo.id);
  if (cuerpo.tipo === "mencion") return avisarMencion(cuerpo.id, cuerpo.para);
  if (cuerpo.tipo === "reto") return avisarReto(cuerpo.id, cuerpo.evento);
  if (cuerpo.tipo === "anuncio") return avisarAnuncio(cuerpo.id);
  if (cuerpo.tipo === "reporte_chat") return avisarReporteChat(cuerpo.mensaje_id, cuerpo.motivo);
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

  const bearer = await accessToken();
  const muertos: string[] = [];
  await Promise.all(tokens.map(async (t) => {
    const mio = cuenta.get(t.user_id) ?? 0;
    const en = t.idioma === "en";
    const cola = en
      ? (mio < n ? "you're losing 😬" : mio === n ? "you're tied 👀" : "you're still winning 👑")
      : (mio < n ? "vas perdiendo 😬" : mio === n ? "van empatados 👀" : "todavía le ganas 👑");
    const notification = en
      ? { title: `💩 ${perfil.username} pooped`, body: `${perfil.username} pooped ${n} ${n === 1 ? "time" : "times"} today... ${cola}` }
      : { title: `💩 ${perfil.username} cagó`, body: `${perfil.username} cagó ${n} ${n === 1 ? "vez" : "veces"} hoy... ${cola}` };
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token: t.token,
          notification,
          data: { tipo: "cagada", user_id },
          android: { notification: { channel_id: "cagadas" } },
        },
      }),
    });
    if (!res.ok) {
      const err = await res.text();
      // Token de una app desinstalada: se borra.
      if (res.status === 404 || err.includes("UNREGISTERED")) muertos.push(t.token);
      else console.error("FCM", res.status, err);
    }
  }));
  if (muertos.length) await db.from("push_tokens").delete().in("token", muertos);

  return Response.json({ enviados: tokens.length - muertos.length, borrados: muertos.length });
});

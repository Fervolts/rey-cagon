// Llamada por el trigger cagadas_avisar (pg_net) en cada cagada nueva.
// Manda un push FCM a los seguidores de quien cagó: "Fulanito cagó N veces hoy... vas perdiendo".
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT")!);
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

// Venezuela no tiene horario de verano: el día arranca a las 04:00 UTC (igual que leaderboard()).
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

// OAuth2 de la cuenta de servicio (JWT RS256 firmado aquí mismo, sin librerías de Google).
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

// Trigger follows_avisar: "X te empezó a seguir", a todos los teléfonos del seguido.
async function avisarFollow(follower: string, followed: string) {
  const [{ data: perfil }, { data: tokens }, { data: devuelta }] = await Promise.all([
    db.from("profiles").select("username").eq("id", follower).single(),
    db.from("push_tokens").select("token").eq("user_id", followed),
    db.from("follows").select("follower").eq("follower", followed).eq("followed", follower).maybeSingle(),
  ]);
  if (!perfil || !tokens?.length) return Response.json({ enviados: 0 });
  const body = devuelta
    ? "Ya lo sigues. Que empiece la guerra 💩"
    : "Síguelo de vuelta para saber cuánto caga 💩";
  const muertos: string[] = [];
  await Promise.all(tokens.map(async (t) => {
    const res = await enviar(t.token, `👀 ${perfil.username} te empezó a seguir`, body, { tipo: "follow", user_id: follower });
    if (!res.ok) {
      const err = await res.text();
      if (res.status === 404 || err.includes("UNREGISTERED")) muertos.push(t.token);
      else console.error("FCM", res.status, err);
    }
  }));
  if (muertos.length) await db.from("push_tokens").delete().in("token", muertos);
  return Response.json({ enviados: tokens.length - muertos.length });
}

// scripts/publicar.sh: "hay versión nueva" a los teléfonos con un build menor que ya saben actualizarse
// (app_build lo reporta la app desde 1.8.2; null = más vieja, sin push).
async function avisarVersion(version: string, build: number) {
  const { data: tokens } = await db.from("push_tokens").select("token").lt("app_build", build);
  if (!tokens?.length) return Response.json({ enviados: 0 });
  const muertos: string[] = [];
  await Promise.all(tokens.map(async (t) => {
    const res = await enviar(
      t.token,
      "Actualízame, mojón 💩",
      `La versión ${version} ya está lista. Toca para instalarla.`,
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

Deno.serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== Deno.env.get("WEBHOOK_SECRET")) {
    return new Response("no", { status: 401 });
  }
  const cuerpo = await req.json();
  if (cuerpo.tipo === "follow") return avisarFollow(cuerpo.follower, cuerpo.followed);
  if (cuerpo.tipo === "version") return avisarVersion(cuerpo.version, cuerpo.build);
  const { user_id } = cuerpo;

  const { data: seguidores } = await db.from("follows").select("follower").eq("followed", user_id);
  if (!seguidores?.length) return Response.json({ enviados: 0 });

  const [{ data: perfil }, { data: hoy }, { data: tokens }] = await Promise.all([
    db.from("profiles").select("username").eq("id", user_id).single(),
    db.from("cagadas").select("user_id").gte("created_at", inicioDelDia()),
    db.from("push_tokens").select("token, user_id").in("user_id", seguidores.map((s) => s.follower)),
  ]);
  if (!perfil || !tokens?.length) return Response.json({ enviados: 0 });

  const cuenta = new Map<string, number>();
  for (const c of hoy ?? []) cuenta.set(c.user_id, (cuenta.get(c.user_id) ?? 0) + 1);
  const n = cuenta.get(user_id) ?? 0;
  const veces = n === 1 ? "vez" : "veces";

  const bearer = await accessToken();
  const muertos: string[] = [];
  await Promise.all(tokens.map(async (t) => {
    const mio = cuenta.get(t.user_id) ?? 0;
    const cola = mio < n ? "vas perdiendo 😬" : mio === n ? "van empatados 👀" : "todavía le ganas 👑";
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token: t.token,
          notification: { title: `💩 ${perfil.username} cagó`, body: `${perfil.username} cagó ${n} ${veces} hoy... ${cola}` },
          data: { tipo: "cagada", user_id },
          android: { notification: { channel_id: "cagadas" } },
        },
      }),
    });
    if (!res.ok) {
      const err = await res.text();
      // Token de una app desinstalada o reinstalada: se borra para no seguir intentando.
      if (res.status === 404 || err.includes("UNREGISTERED")) muertos.push(t.token);
      else console.error("FCM", res.status, err);
    }
  }));
  if (muertos.length) await db.from("push_tokens").delete().in("token", muertos);

  return Response.json({ enviados: tokens.length - muertos.length, borrados: muertos.length });
});

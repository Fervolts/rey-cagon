-- Dibujo v2 (editor nuevo): colores libres "rrggbb", 8 grosores y herramienta por trazo.
-- {"v":2,"fondo":"rrggbb","trazos":[{"c":"rrggbb","g":1..8,"h":"pincel|plumon|spray|borrador|sello","p":[x,y,...]}]}
-- Mismos topes que v1. El sello lleva un solo punto. v1 se sigue aceptando igual que antes (apps 72 y 73).
-- Espejo exacto: dibujoInvalido() en lib/muro_dibujo.dart. Si se cambia uno, se cambia el otro.
create or replace function public.dibujo_invalido(d jsonb)
returns text language plpgsql immutable set search_path = '' as $$
declare
  t jsonb;
  n int;
  total int := 0;
  v1 boolean;
  claves_trazo text[];
  patron_g text;
begin
  if jsonb_typeof(d) <> 'object' then return 'no es un objeto'; end if;
  if (select array_agg(k order by k) from jsonb_object_keys(d) k) <> array['fondo', 'trazos', 'v'] then
    return 'claves de más o de menos';
  end if;
  v1 := d -> 'v' = '1'::jsonb;
  if not v1 and d -> 'v' <> '2'::jsonb then return 'versión desconocida'; end if;
  -- Fuera del IF: un CASE dentro de la condición de un IF de plpgsql corta en su primer THEN.
  claves_trazo := case when v1 then array['c', 'g', 'p'] else array['c', 'g', 'h', 'p'] end;
  patron_g := case when v1 then '^[1-4]$' else '^[1-8]$' end;
  if v1 and (jsonb_typeof(d -> 'fondo') <> 'number' or (d ->> 'fondo') !~ '^\d{1,2}$' or (d ->> 'fondo')::int > 15)
     or not v1 and (jsonb_typeof(d -> 'fondo') <> 'string' or (d ->> 'fondo') !~ '^[0-9a-f]{6}$') then
    return 'fondo fuera de rango';
  end if;
  if jsonb_typeof(d -> 'trazos') <> 'array' then return 'trazos no es una lista'; end if;
  n := jsonb_array_length(d -> 'trazos');
  if n < 1 or n > 400 then return 'entre 1 y 400 trazos'; end if;
  for t in select x from jsonb_array_elements(d -> 'trazos') x loop
    if jsonb_typeof(t) <> 'object' then return 'trazo que no es objeto'; end if;
    if (select array_agg(k order by k) from jsonb_object_keys(t) k) <> claves_trazo then
      return 'trazo con claves de más o de menos';
    end if;
    if v1 and (jsonb_typeof(t -> 'c') <> 'number' or (t ->> 'c') !~ '^\d{1,2}$' or (t ->> 'c')::int > 15)
       or not v1 and (jsonb_typeof(t -> 'c') <> 'string' or (t ->> 'c') !~ '^[0-9a-f]{6}$') then
      return 'color fuera de rango';
    end if;
    if jsonb_typeof(t -> 'g') <> 'number' or (t ->> 'g') !~ patron_g then
      return 'grosor fuera de rango';
    end if;
    if not v1 and (jsonb_typeof(t -> 'h') <> 'string'
                   or (t ->> 'h') not in ('pincel', 'plumon', 'spray', 'borrador', 'sello')) then
      return 'herramienta desconocida';
    end if;
    if jsonb_typeof(t -> 'p') <> 'array' then return 'puntos no es una lista'; end if;
    n := jsonb_array_length(t -> 'p');
    if n < 2 or n > 4000 or n % 2 <> 0 or (not v1 and t ->> 'h' = 'sello' and n <> 2) then
      return 'trazo con número de puntos inválido';
    end if;
    total := total + n;
    if total > 30000 then return 'demasiados puntos'; end if;
    if exists (select 1 from jsonb_array_elements(t -> 'p') e
               where jsonb_typeof(e) <> 'number' or e::text !~ '^\d{1,4}$' or e::text::int > 1000) then
      return 'coordenada fuera de rango';
    end if;
  end loop;
  return null;
end;
$$;

-- Las apps 72 y 73 solo saben leer v1 y solo usan muro_feed: ahí no salen los posts con dibujo v2
-- (se verían vacíos). La app nueva usa muro_feed_tarjetas, que los trae todos.
create or replace function public.muro_feed(p_antes timestamptz default null, p_amigos boolean default false, p_limite int default 20)
returns table (
  id bigint, user_id uuid, texto text, dibujo jsonb, created_at timestamptz,
  likes bigint, yo_like boolean, comentarios bigint,
  username text, avatar text, sombrero text, lentes text, mascota text, cagadas integer,
  lentes_x real, lentes_y real, sombrero_x real, sombrero_y real, lentes_escala real, sombrero_escala real
)
language sql stable security definer set search_path = '' as $$
  select m.id, m.user_id, m.texto, m.dibujo, m.created_at,
         (select count(*) from public.muro_likes l where l.post_id = m.id),
         exists (select 1 from public.muro_likes l where l.post_id = m.id and l.user_id = (select auth.uid())),
         (select count(*) from public.muro_comentarios c where c.post_id = m.id and not public.hay_bloqueo(c.user_id)),
         p.username, p.avatar, p.sombrero, p.lentes, p.mascota, p.cagadas,
         p.lentes_x, p.lentes_y, p.sombrero_x, p.sombrero_y, p.lentes_escala, p.sombrero_escala
  from public.muro m
  join public.profiles p on p.id = m.user_id
  where (select auth.uid()) is not null
    and m.tarjeta is null
    and (m.dibujo is null or m.dibujo -> 'v' = '1'::jsonb)
    and (p_antes is null or m.created_at < p_antes)
    and (not m.oculto or m.user_id = (select auth.uid()) or public.es_admin())
    and not public.hay_bloqueo(m.user_id)
    and (not p_amigos
         or m.user_id = (select auth.uid())
         or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = m.user_id))
  order by m.created_at desc, m.id desc
  limit least(greatest(coalesce(p_limite, 20), 1), 50);
$$;

-- Temporadas del Imperio (2.13.0). El flag `temporadas` de imperio_flags trae la lista
-- [{id, desde, hasta, x}] (desde y hasta timestamptz en ISO 8601; x multiplica la producción, 1 = solo aspecto).
-- El teléfono aplica una temporada solo si viene en el flag y la hora cae en [desde, hasta) (lib/imperio/temporadas.dart).
--   - dia_retrete: Día Mundial del Retrete, 19 nov hora de Caracas, todo x3 y el logro `dia_retrete`.
--   - navidad: diciembre hora de Caracas, el mojón dorado sale como hallaca dorada (x1).
-- Además: imperio_guardar estira su tope blando con el x de la temporada, y el gorro de Santa (sombrero '🎅')
-- se gana cagando al menos una vez en diciembre, para siempre (fila en premios + caso en validar_desbloqueos).

insert into public.imperio_flags (clave, valor, nota) values
  ('temporadas',
   '[{"id": "dia_retrete", "desde": "2026-11-19T00:00:00-04:00", "hasta": "2026-11-20T00:00:00-04:00", "x": 3},
     {"id": "navidad", "desde": "2026-12-01T00:00:00-04:00", "hasta": "2027-01-01T00:00:00-04:00", "x": 1}]',
   'Temporadas del Imperio: lista de {id, desde, hasta, x}; x multiplica la producción (tope 10)')
on conflict (clave) do nothing;

-- Mayor x de las temporadas del flag que se pisan con [p_desde, p_hasta]. Entre 1 y 10, como en el teléfono.
-- Un flag mal escrito no debe tumbar imperio_guardar: cualquier error da 1.
create or replace function public.imperio_temporada_x(p_desde timestamptz, p_hasta timestamptz)
returns double precision
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  lista jsonb;
  t jsonb;
  x double precision := 1;
  tx double precision;
begin
  select f.valor into lista from public.imperio_flags f where f.clave = 'temporadas' and f.activo;
  if lista is null or jsonb_typeof(lista) <> 'array' then return 1; end if;
  for t in select * from jsonb_array_elements(lista) loop
    begin
      if jsonb_typeof(t) <> 'object' or jsonb_typeof(t -> 'x') <> 'number' then continue; end if;
      if (t ->> 'desde')::timestamptz < p_hasta and (t ->> 'hasta')::timestamptz > p_desde then
        tx := least(greatest((t ->> 'x')::double precision, 1), 10);
        if tx > x then x := tx; end if;
      end if;
    exception when others then
      continue;
    end;
  end loop;
  return x;
exception when others then
  return 1;
end $function$;

revoke all on function public.imperio_temporada_x(timestamptz, timestamptz) from public, anon, authenticated;

-- Igual que en 20261031230000_imperio_guardar_jaladas.sql, salvo el tope: con una temporada x3 (Día Mundial del
-- Retrete) un jugador honesto en Fiebre y pujando pasa del margen de 30 veces el MJ/s. El margen se multiplica por el
-- mayor x de las temporadas que tocan el tramo desde el último guardado (con las mismas 2 h de colchón).
create or replace function public.imperio_guardar(p_estado jsonb, p_mj_total double precision, p_mps double precision)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  seg double precision;
  permitido double precision;
  nuevo_total double precision;
  nuevo_mps double precision := greatest(coalesce(p_mps, 0), 0);
  recortado boolean := false;
  jaladas_copia int;
begin
  if uid is null then raise exception 'no autenticado'; end if;
  if p_estado is null or pg_column_size(p_estado) > 65536 then
    raise exception 'estado demasiado grande';
  end if;

  select * into fila from public.imperio where user_id = uid for update;
  if not found then raise exception 'imperio no existe'; end if;

  jaladas_copia := case when jsonb_typeof(p_estado -> 'jaladas') = 'number' then (p_estado ->> 'jaladas')::numeric::int else 0 end;
  if jaladas_copia < fila.jaladas then
    return jsonb_build_object('mj_total', fila.mj_total, 'recortado', false, 'guardado', fila.guardado, 'ignorado', true);
  end if;

  seg := extract(epoch from now() - fila.guardado);
  permitido := fila.mj_total + (seg + 7200) * greatest(fila.mps, nuevo_mps, 1) * 30
    * public.imperio_temporada_x(fila.guardado - interval '2 hours', now()) + 100000;
  nuevo_total := least(greatest(coalesce(p_mj_total, 0), fila.mj_total), permitido);
  if coalesce(p_mj_total, 0) > nuevo_total then recortado := true; end if;

  update public.imperio
    set estado = p_estado, mj_total = nuevo_total, mps = nuevo_mps, guardado = now()
    where user_id = uid;

  return jsonb_build_object('mj_total', nuevo_total, 'recortado', recortado, 'guardado', now());
end $function$;

-- Gorro de Santa. Fila en el catálogo (sin `exclusivo`: el permiso lo da el caso propio en validar_desbloqueos).
insert into public.desbloqueos (ranura, emoji, minimo) values ('sombrero', '🎅', 1)
on conflict (ranura, emoji) do nothing;

-- Cagar en diciembre (hora de Caracas) deja el gorro en premios, para que la app lo muestre en el editor
-- (lee premios igual que los exclusivos) y quede aunque después se borre esa cagada.
create or replace function public.premiar_gorro_santa()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if extract(month from new.created_at at time zone 'America/Caracas') = 12 then
    insert into public.premios (user_id, ranura, emoji, motivo)
    values (new.user_id, 'sombrero', '🎅', 'navidad')
    on conflict do nothing;
  end if;
  return new;
end $function$;

revoke all on function public.premiar_gorro_santa() from public, anon, authenticated;

drop trigger if exists cagadas_gorro_santa on public.cagadas;
create trigger cagadas_gorro_santa after insert on public.cagadas
  for each row execute function public.premiar_gorro_santa();

-- Los que ya cagaron en algún diciembre antes de esta migración.
insert into public.premios (user_id, ranura, emoji, motivo)
select distinct c.user_id, 'sombrero', '🎅', 'navidad'
from public.cagadas c
where extract(month from c.created_at at time zone 'America/Caracas') = 12
on conflict do nothing;

-- Igual que en 20261104120000_premios_exclusivos.sql, más el caso del gorro de Santa.
create or replace function public.validar_desbloqueos()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  total bigint;
  r text;
  v text;
  antes text;
begin
  select count(*) into total from public.cagadas where user_id = new.id;
  foreach r in array array['avatar', 'sombrero', 'lentes', 'mascota'] loop
    v := case r when 'avatar' then new.avatar when 'sombrero' then new.sombrero
                when 'lentes' then new.lentes else new.mascota end;
    antes := case r when 'avatar' then old.avatar when 'sombrero' then old.sombrero
                    when 'lentes' then old.lentes else old.mascota end;
    -- Solo se valida lo que cambió: si deshaces cagadas no pierdes lo que ya tenías puesto.
    if v is null or v is not distinct from antes then continue; end if;
    if r <> 'avatar' and not exists (select 1 from public.desbloqueos d where d.ranura = r and d.emoji = v) then
      raise exception 'Accesorio desconocido' using errcode = '23514';
    end if;
    if exists (select 1 from public.desbloqueos d where d.ranura = r and d.emoji = v and d.exclusivo)
       and not exists (select 1 from public.premios pr where pr.user_id = new.id and pr.ranura = r and pr.emoji = v) then
      raise exception 'Eso es un premio exclusivo' using errcode = 'P0001';
    end if;
    -- Gorro de Santa: haber cagado al menos una vez en diciembre (hora de Caracas), de cualquier año.
    if r = 'sombrero' and v = '🎅'
       and not exists (select 1 from public.premios pr where pr.user_id = new.id and pr.ranura = r and pr.emoji = v)
       and not exists (select 1 from public.cagadas c where c.user_id = new.id
                       and extract(month from c.created_at at time zone 'America/Caracas') = 12) then
      raise exception 'El gorro de Santa se gana cagando en diciembre' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.desbloqueos d where d.ranura = r and d.emoji = v and d.minimo > total) then
      raise exception 'Todavía no has desbloqueado eso' using errcode = 'P0001';
    end if;
  end loop;
  return new;
end;
$function$;

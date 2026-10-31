-- imperio_guardar no pisa la partida con una copia que jaló menos veces que el servidor.
-- Una copia así es vieja: la de una app abierta desde antes de jalar (o de un reinicio hecho desde el
-- servidor), o la de una versión sin la cadena (no manda `jaladas`). Se ignora sin error y la app,
-- al volver a cargar, toma la del servidor (usarCopiaLocal prefiere la que jaló más veces).

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
  permitido := fila.mj_total + (seg + 7200) * greatest(fila.mps, nuevo_mps, 1) * 30 + 100000;
  nuevo_total := least(greatest(coalesce(p_mj_total, 0), fila.mj_total), permitido);
  if coalesce(p_mj_total, 0) > nuevo_total then recortado := true; end if;

  update public.imperio
    set estado = p_estado, mj_total = nuevo_total, mps = nuevo_mps, guardado = now()
    where user_id = uid;

  return jsonb_build_object('mj_total', nuevo_total, 'recortado', recortado, 'guardado', now());
end $function$;

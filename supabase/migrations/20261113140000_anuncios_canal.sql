-- Pop-ups de admin solo para un canal: 'directo' (APK de GitHub) o 'play'. null = todos.
-- El canal de cada usuario es el de su token de push más nuevo; los tokens sin canal son de
-- builds viejos, todos de la APK directa. Sin token no hay canal: solo ve los pop-ups para todos.

alter table public.anuncios add column canal text check (canal in ('play', 'directo'));

create or replace function public.mi_canal()
returns text
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(t.canal, 'directo')
    from public.push_tokens t
   where t.user_id = (select auth.uid())
   order by t.updated_at desc
   limit 1
$$;

drop policy anuncios_select on public.anuncios;
create policy anuncios_select on public.anuncios for select to authenticated
  using (canal is null or canal = (select public.mi_canal()) or (select public.es_admin()));

-- El editor de las apps de hoy no tiene selector de canal: un pop-up que manda a la prueba
-- de Play solo tiene sentido para los de la APK directa, así que va solo a ellos.
create or replace function public.anuncios_canal_por_link()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if new.canal is null and new.boton_url ~ '(groups\.google\.com/g/rey-cagon-testers|play\.google\.com/apps/testing/)' then
    new.canal := 'directo';
  end if;
  return new;
end;
$$;

create trigger anuncios_canal_por_link before insert on public.anuncios
  for each row execute function public.anuncios_canal_por_link();

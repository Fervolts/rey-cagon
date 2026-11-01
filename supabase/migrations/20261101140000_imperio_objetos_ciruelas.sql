-- Objetos del Imperio pagables con Ciruelas: 'obj_<id>' en imperio_gastar_ciruelas.
-- Precios iguales a `Objeto.ciruelas` en lib/imperio/catalogo.dart. El efecto lo pone la app.
create or replace function public.imperio_gastar_ciruelas(p_que text) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  precio int;
  saldo bigint;
begin
  if uid is null then raise exception 'no autenticado'; end if;
  precio := case p_que
    when 'cagada_fresca' then 3
    when 'produccion_2h' then 5
    when 'robot_24h' then 10
    when 'obj_ambientador' then 2
    when 'obj_laxante' then 1
    when 'obj_papel' then 2
    when 'obj_robot' then 3
  end;
  if precio is null then raise exception 'oferta desconocida'; end if;
  update public.imperio set ciruelas = ciruelas - precio
   where user_id = uid and ciruelas >= precio
   returning ciruelas into saldo;
  return coalesce(saldo, -1);
end $$;

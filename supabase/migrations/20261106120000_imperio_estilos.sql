-- Tienda de estilo del Imperio: temas, efectos del botón CAGUÉ y movimientos del avatar.
-- Son cosméticos que se compran una vez y se quedan para siempre (jalar la cadena no los borra).
-- El catálogo es copia de lib/imperio/estilos.dart (test/imperio_estilos_test.dart revisa que coincidan).
-- El saldo de MJ y los Rollos viven en el teléfono: aquí solo se revisa por encima (con lo último guardado) y se anota
-- la compra. El teléfono descuenta y guarda.

create table public.imperio_estilos_catalogo (
  id text primary key,
  tipo text not null check (tipo in ('tema', 'efecto', 'movimiento')),
  mj double precision not null default 0,
  rollos int not null default 0,
  cagadas int not null default 0
);
alter table public.imperio_estilos_catalogo enable row level security;
-- Sin políticas: solo lo leen las funciones de abajo.

insert into public.imperio_estilos_catalogo (id, tipo, mj, rollos, cagadas) values
  ('tema_clasico', 'tema', 0, 0, 0),
  ('tema_porcelana', 'tema', 1e5, 0, 0),
  ('tema_cloaca', 'tema', 1e6, 0, 0),
  ('tema_papel', 'tema', 1e7, 0, 0),
  ('tema_gameboy', 'tema', 1e8, 0, 0),
  ('tema_neon', 'tema', 1e9, 0, 0),
  ('tema_marmol', 'tema', 0, 2, 150),
  ('tema_oro', 'tema', 0, 10, 0),
  ('efecto_ninguno', 'efecto', 0, 0, 0),
  ('efecto_confeti', 'efecto', 1e5, 0, 0),
  ('efecto_papel', 'efecto', 1e6, 0, 0),
  ('efecto_rayo', 'efecto', 1e7, 0, 0),
  ('efecto_remolino', 'efecto', 1e8, 0, 0),
  ('efecto_fuegos', 'efecto', 1e9, 0, 0),
  ('mov_ninguno', 'movimiento', 0, 0, 0),
  ('mov_respirar', 'movimiento', 5e4, 0, 0),
  ('mov_rebotar', 'movimiento', 5e5, 0, 0),
  ('mov_saludar', 'movimiento', 5e6, 0, 0),
  ('mov_temblar', 'movimiento', 5e7, 0, 0),
  ('mov_girar', 'movimiento', 5e8, 0, 0),
  ('mov_flotar', 'movimiento', 5e9, 0, 0),
  ('mov_bailar', 'movimiento', 5e10, 0, 0),
  ('mov_brillo', 'movimiento', 0, 3, 0);

-- Lo que cada quien compró. Los gratis no se anotan: se tienen siempre.
create table public.imperio_estilos (
  user_id uuid not null references public.profiles(id) on delete cascade,
  id text not null references public.imperio_estilos_catalogo(id),
  creado timestamptz not null default now(),
  primary key (user_id, id)
);
alter table public.imperio_estilos enable row level security;
create policy "imperio_estilos_read_own" on public.imperio_estilos
  for select to authenticated using ((select auth.uid()) = user_id);

-- Multiplicador del precio en MJ (los Rollos y las cagadas no cambian). Igual que en lib/imperio/flags.dart.
insert into public.imperio_flags (clave, valor, nota) values
  ('estilo_precio_mult', '1', 'Multiplica el precio en MJ de la tienda de estilo')
on conflict (clave) do nothing;

-- Compra un estilo. Devuelve {"comprados": [ids]} con todo lo que tienes.
create function public.imperio_estilo_comprar(p_id text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  est public.imperio_estilos_catalogo;
  mult double precision;
  mis_cagadas int;
  mi_total double precision;
  mis_rollos double precision;
  lista text[];
begin
  if uid is null then raise exception 'Sin sesión' using errcode = 'P0001'; end if;
  select * into est from public.imperio_estilos_catalogo c where c.id = p_id;
  if not found then raise exception 'Ese estilo no existe' using errcode = 'P0001'; end if;
  if est.mj <= 0 and est.rollos <= 0 and est.cagadas <= 0 then
    raise exception 'Ese estilo es gratis' using errcode = 'P0001';
  end if;

  if not exists (select 1 from public.imperio_estilos e where e.user_id = uid and e.id = p_id) then
    mult := coalesce((select (f.valor #>> '{}')::double precision from public.imperio_flags f
      where f.clave = 'estilo_precio_mult' and f.activo and jsonb_typeof(f.valor) = 'number'), 1);
    mult := least(greatest(mult, 0.01), 1000);

    select p.cagadas into mis_cagadas from public.profiles p where p.id = uid;
    if coalesce(mis_cagadas, 0) < est.cagadas then
      raise exception 'Te faltan cagadas: necesitas %', est.cagadas using errcode = 'P0001';
    end if;

    select im.mj_total, public.imperio_numero(im.estado ->> 'rollos') into mi_total, mis_rollos
      from public.imperio im where im.user_id = uid;
    -- Por encima: el saldo real está en el teléfono, aquí solo se mira lo ganado en total.
    if est.mj > 0 and coalesce(mi_total, 0) < est.mj * mult then
      raise exception 'Te faltan MJ' using errcode = 'P0001';
    end if;
    if est.rollos > 0 and coalesce(mis_rollos, 0) < est.rollos then
      raise exception 'Te faltan Rollos' using errcode = 'P0001';
    end if;

    insert into public.imperio_estilos (user_id, id) values (uid, p_id) on conflict do nothing;
  end if;

  select coalesce(array_agg(e.id order by e.creado), '{}') into lista from public.imperio_estilos e where e.user_id = uid;
  return jsonb_build_object('comprados', to_jsonb(lista));
end;
$$;

-- Los ids que compraste.
create function public.imperio_estilos_mios() returns text[]
language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(e.id order by e.creado), '{}') from public.imperio_estilos e where e.user_id = auth.uid();
$$;

revoke all on function public.imperio_estilo_comprar(text) from public, anon;
grant execute on function public.imperio_estilo_comprar(text) to authenticated;
revoke all on function public.imperio_estilos_mios() from public, anon;
grant execute on function public.imperio_estilos_mios() to authenticated;

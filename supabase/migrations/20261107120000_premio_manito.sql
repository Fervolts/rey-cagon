-- Premio exclusivo nuevo: la manito clicker de oro (mascota). Lo da el servidor a mano en `premios`.
insert into public.desbloqueos (ranura, emoji, minimo, exclusivo) values ('mascota', '👆', 1, true)
on conflict (ranura, emoji) do update set exclusivo = true;

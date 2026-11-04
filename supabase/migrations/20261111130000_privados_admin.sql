-- Privados: el admin ya no lee todos los dm, solo los mensajes de dm que alguien reportó.
--
-- Copia idéntica de mensajes_select de 20261111120000_privados.sql; solo cambia la rama 'dm:%':
-- las dos partes siguen viendo todo lo suyo igual (sin bloqueo, ocultos solo los propios) y el admin ve
-- únicamente los mensajes con al menos una fila en public.mensaje_reportes. El exists pasa por la RLS de
-- mensaje_reportes (el admin las ve todas con es_admin), que no consulta mensajes: no hay recursión.

begin;

drop policy mensajes_select on public.mensajes;
create policy mensajes_select on public.mensajes for select using (
  (public.sala_publica(sala) and not public.hay_bloqueo(user_id)
   and ((not oculto) or user_id = (select auth.uid()) or public.es_admin()))
  or (sala = 'soporte' and (hilo = (select auth.uid()) or public.es_admin()))
  or (sala like 'cloaca:%' and ((public.cloaca_es_mia(sala) and not public.hay_bloqueo(user_id)
                                 and ((not oculto) or user_id = (select auth.uid())))
                                or public.es_admin()))
  or (sala like 'dm:%' and ((public.dm_soy_parte(sala) and not public.hay_bloqueo(user_id)
                             and ((not oculto) or user_id = (select auth.uid())))
                            or (public.es_admin()
                                and exists (select 1 from public.mensaje_reportes r where r.mensaje_id = mensajes.id)))));

commit;

notify pgrst, 'reload schema';

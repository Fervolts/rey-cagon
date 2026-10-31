-- Análisis del Imperio: consultas de solo lectura para correr a mano en el editor SQL. NO es una migración.
-- Cada sección se corre sola. Todas se parten por variante de una flag: cambiar la clave en el CTE `p`
-- (las que no tienen variantes salen en '(sin)'; quien cayó fuera de los pesos sale en 'base').
-- Días calendario en hora de Venezuela. Catálogo de eventos: lib/imperio/telemetria.dart.


-- =====================================================================================================
-- 1. Jugadores activos por día
-- =====================================================================================================
with p as (select 'precio_crecimiento'::text as clave),
ev as (
  select e.*, coalesce(a.variante, '(sin)') as variante, (e.creado at time zone 'America/Caracas')::date as dia
  from public.imperio_eventos e
  left join public.imperio_asignaciones a on a.user_id = e.user_id and a.clave = (select clave from p)
)
select dia, variante, count(distinct user_id) as activos, count(*) filter (where evento = 'sesion_inicio') as sesiones
from ev group by dia, variante order by dia desc, variante;


-- =====================================================================================================
-- 2. Retención D1 / D7 desde la primera sesion_inicio (cohorte = día de la primera sesión)
-- =====================================================================================================
with p as (select 'precio_crecimiento'::text as clave),
dias as (
  select distinct e.user_id, (e.creado at time zone 'America/Caracas')::date as dia
  from public.imperio_eventos e where e.evento = 'sesion_inicio'
),
primero as (select user_id, min(dia) as d0 from dias group by user_id),
c as (
  select pr.user_id, pr.d0, coalesce(a.variante, '(sin)') as variante,
         exists (select 1 from dias x where x.user_id = pr.user_id and x.dia = pr.d0 + 1) as d1,
         exists (select 1 from dias x where x.user_id = pr.user_id and x.dia = pr.d0 + 7) as d7,
         exists (select 1 from dias x where x.user_id = pr.user_id and x.dia between pr.d0 + 1 and pr.d0 + 7) as volvio_semana
  from primero pr
  left join public.imperio_asignaciones a on a.user_id = pr.user_id and a.clave = (select clave from p)
),
hoy as (select (now() at time zone 'America/Caracas')::date as h)
select d0 as cohorte, variante, count(*) as jugadores,
       case when d0 + 1 < (select h from hoy) then round(100.0 * avg(d1::int), 1) end as d1_pct,
       case when d0 + 7 < (select h from hoy) then round(100.0 * avg(d7::int), 1) end as d7_pct,
       case when d0 + 7 < (select h from hoy) then round(100.0 * avg(volvio_semana::int), 1) end as volvio_1a7_pct
from c group by d0, variante order by d0 desc, variante;


-- =====================================================================================================
-- 3. Duración de las sesiones (sesion_fin.segundos)
-- =====================================================================================================
with p as (select 'precio_crecimiento'::text as clave),
s as (
  select coalesce(a.variante, '(sin)') as variante, (e.datos->>'segundos')::numeric as seg
  from public.imperio_eventos e
  left join public.imperio_asignaciones a on a.user_id = e.user_id and a.clave = (select clave from p)
  where e.evento = 'sesion_fin' and jsonb_typeof(e.datos->'segundos') = 'number'
)
select variante, count(*) as sesiones,
       round(percentile_cont(0.5) within group (order by seg)) as mediana_s,
       round(percentile_cont(0.9) within group (order by seg)) as p90_s,
       round(100.0 * avg((seg < 30)::int), 1) as menos_30s_pct,
       round(100.0 * avg((seg >= 30 and seg < 60)::int), 1) as de_30_60s_pct,
       round(100.0 * avg((seg >= 60 and seg < 180)::int), 1) as de_1_3m_pct,
       round(100.0 * avg((seg >= 180 and seg < 600)::int), 1) as de_3_10m_pct,
       round(100.0 * avg((seg >= 600 and seg < 1800)::int), 1) as de_10_30m_pct,
       round(100.0 * avg((seg >= 1800)::int), 1) as mas_30m_pct
from s group by variante order by variante;


-- =====================================================================================================
-- 4. Embudo: cuántos llegan a cada edificio y mejora, y cuánto tardan en comprarla por primera vez
--    (segundos de juego activo = seg_partida; días calendario desde su primera sesión)
-- =====================================================================================================
with p as (select 'precio_crecimiento'::text as clave),
jug as (
  select e.user_id, min(e.creado) as t0, coalesce(min(a.variante), '(sin)') as variante
  from public.imperio_eventos e
  left join public.imperio_asignaciones a on a.user_id = e.user_id and a.clave = (select clave from p)
  where e.evento = 'sesion_inicio' group by e.user_id
),
total as (select variante, count(*) as n from jug group by variante),
compras as (
  select e.evento as tipo, e.datos->>'id' as id, e.user_id, min(e.creado) as t,
         min(case when jsonb_typeof(e.datos->'seg_partida') = 'number' then (e.datos->>'seg_partida')::numeric end) as seg
  from public.imperio_eventos e
  where e.evento in ('edificio', 'mejora') and e.datos ? 'id'
  group by e.evento, e.datos->>'id', e.user_id
)
select c.tipo, c.id, j.variante, count(*) as jugadores, round(100.0 * count(*) / max(t.n), 1) as llegan_pct,
       round(percentile_cont(0.5) within group (order by c.seg)) as mediana_seg_activos,
       round(percentile_cont(0.9) within group (order by c.seg)) as p90_seg_activos,
       round((percentile_cont(0.5) within group (order by extract(epoch from c.t - j.t0) / 86400))::numeric, 2) as mediana_dias
from compras c join jug j using (user_id) join total t using (variante)
group by c.tipo, c.id, j.variante order by c.tipo, mediana_seg_activos nulls last, j.variante;


-- =====================================================================================================
-- 5. Mojón dorado: tocados contra perdidos, y qué efecto salió
-- =====================================================================================================
with p as (select 'precio_crecimiento'::text as clave),
ev as (
  select e.*, coalesce(a.variante, '(sin)') as variante from public.imperio_eventos e
  left join public.imperio_asignaciones a on a.user_id = e.user_id and a.clave = (select clave from p)
  where e.evento in ('dorado_aparece', 'dorado_toca', 'dorado_pierde')
)
select variante,
       count(*) filter (where evento = 'dorado_aparece') as aparecen,
       count(*) filter (where evento = 'dorado_toca') as tocados,
       count(*) filter (where evento = 'dorado_pierde') as perdidos,
       round(100.0 * count(*) filter (where evento = 'dorado_toca')
             / nullif(count(*) filter (where evento in ('dorado_toca', 'dorado_pierde')), 0), 1) as tocados_pct
from ev group by variante order by variante;

-- Qué efecto salió al tocarlo

with p as (select 'precio_crecimiento'::text as clave)
select coalesce(a.variante, '(sin)') as variante, e.datos->>'efecto' as efecto, count(*) as veces
from public.imperio_eventos e
left join public.imperio_asignaciones a on a.user_id = e.user_id and a.clave = (select clave from p)
where e.evento = 'dorado_toca' group by 1, 2 order by 1, 3 desc;


-- =====================================================================================================
-- 6. Atascos: destapados (perfectos, por robot) contra perdidos
-- =====================================================================================================
with p as (select 'precio_crecimiento'::text as clave),
ev as (
  select e.*, coalesce(a.variante, '(sin)') as variante from public.imperio_eventos e
  left join public.imperio_asignaciones a on a.user_id = e.user_id and a.clave = (select clave from p)
  where e.evento in ('atasco_aparece', 'atasco_destapa', 'atasco_pierde')
)
select variante,
       count(*) filter (where evento = 'atasco_aparece') as aparecen,
       count(*) filter (where evento = 'atasco_destapa') as destapados,
       count(*) filter (where evento = 'atasco_destapa' and datos->>'perfecto' = 'true') as perfectos,
       count(*) filter (where evento = 'atasco_destapa' and datos->>'robot' = 'true') as por_robot,
       count(*) filter (where evento = 'atasco_pierde') as perdidos,
       round(100.0 * count(*) filter (where evento = 'atasco_destapa')
             / nullif(count(*) filter (where evento in ('atasco_destapa', 'atasco_pierde')), 0), 1) as destapados_pct,
       round(percentile_cont(0.5) within group (order by (datos->>'ms')::numeric)
             filter (where evento = 'atasco_destapa' and datos->>'robot' <> 'true' and jsonb_typeof(datos->'ms') = 'number')) as mediana_ms_a_mano
from ev group by variante order by variante;


-- =====================================================================================================
-- 7. Objetos comprados y usados, por id
-- =====================================================================================================
with p as (select 'precio_crecimiento'::text as clave)
select e.datos->>'id' as objeto, coalesce(a.variante, '(sin)') as variante,
       count(*) filter (where e.evento = 'objeto_compra') as compras,
       count(*) filter (where e.evento = 'objeto_uso') as usos,
       count(distinct e.user_id) filter (where e.evento = 'objeto_compra') as compradores,
       count(distinct e.user_id) filter (where e.evento = 'objeto_uso') as usuarios
from public.imperio_eventos e
left join public.imperio_asignaciones a on a.user_id = e.user_id and a.clave = (select clave from p)
where e.evento in ('objeto_compra', 'objeto_uso') group by 1, 2 order by 1, 2;


-- =====================================================================================================
-- 8. Logros: qué % de los jugadores llega a cada uno
-- =====================================================================================================
with p as (select 'precio_crecimiento'::text as clave),
jug as (
  select e.user_id, coalesce(min(a.variante), '(sin)') as variante from public.imperio_eventos e
  left join public.imperio_asignaciones a on a.user_id = e.user_id and a.clave = (select clave from p)
  where e.evento = 'sesion_inicio' group by e.user_id
),
total as (select variante, count(*) as n from jug group by variante)
select e.datos->>'id' as logro, j.variante, count(distinct e.user_id) as jugadores,
       round(100.0 * count(distinct e.user_id) / max(t.n), 1) as llegan_pct
from public.imperio_eventos e join jug j using (user_id) join total t using (variante)
where e.evento = 'logro' group by 1, 2 order by llegan_pct desc, 1, 2;


-- =====================================================================================================
-- 9. Vueltas offline: cuántas con el tanque lleno (estuvo fuera más que el tope)
-- =====================================================================================================
with p as (select 'precio_crecimiento'::text as clave),
o as (
  select e.user_id, coalesce(a.variante, '(sin)') as variante, e.datos->>'tope_lleno' = 'true' as lleno,
         case when jsonb_typeof(e.datos->'segundos') = 'number' then (e.datos->>'segundos')::numeric end as seg
  from public.imperio_eventos e
  left join public.imperio_asignaciones a on a.user_id = e.user_id and a.clave = (select clave from p)
  where e.evento = 'offline'
)
select variante, count(*) as vueltas, round(100.0 * avg(lleno::int), 1) as tanque_lleno_pct,
       count(distinct user_id) as jugadores, count(distinct user_id) filter (where lleno) as jugadores_con_lleno,
       round((percentile_cont(0.5) within group (order by seg) / 3600)::numeric, 2) as mediana_horas_fuera
from o group by variante order by variante;


-- =====================================================================================================
-- 10. Descargas (cagadas reales que llegaron al Imperio)
-- =====================================================================================================
with p as (select 'precio_crecimiento'::text as clave)
select coalesce(a.variante, '(sin)') as variante, count(*) as descargas, count(distinct e.user_id) as jugadores,
       round(count(*)::numeric / nullif(count(distinct e.user_id), 0), 2) as por_jugador,
       sum(case when jsonb_typeof(e.datos->'cagadas') = 'number' then (e.datos->>'cagadas')::numeric end) as cagadas
from public.imperio_eventos e
left join public.imperio_asignaciones a on a.user_id = e.user_id and a.clave = (select clave from p)
where e.evento = 'descarga' group by 1 order by 1;


-- =====================================================================================================
-- 11. Minijuegos "próximamente" más tocados
-- =====================================================================================================
with p as (select 'precio_crecimiento'::text as clave)
select e.datos->>'id' as minijuego, coalesce(a.variante, '(sin)') as variante, count(*) as toques,
       count(distinct e.user_id) as jugadores
from public.imperio_eventos e
left join public.imperio_asignaciones a on a.user_id = e.user_id and a.clave = (select clave from p)
where e.evento = 'minijuego_toca' group by 1, 2 order by toques desc;


-- =====================================================================================================
-- 12. Todos los eventos por día (pestana_abre, sala_abre, bienvenida, ficha_usa, error...)
-- =====================================================================================================
with p as (select 'precio_crecimiento'::text as clave)
select (e.creado at time zone 'America/Caracas')::date as dia, e.evento, coalesce(a.variante, '(sin)') as variante,
       count(*) as veces, count(distinct e.user_id) as jugadores
from public.imperio_eventos e
left join public.imperio_asignaciones a on a.user_id = e.user_id and a.clave = (select clave from p)
group by 1, 2, 3 order by 1 desc, 4 desc;

-- Errores por sitio, últimos 7 días
select e.datos->>'donde' as donde, e.version_app, count(*) as veces, count(distinct e.user_id) as jugadores
from public.imperio_eventos e
where e.evento = 'error' and e.creado > now() - interval '7 days'
group by 1, 2 order by 3 desc;


-- =====================================================================================================
-- 13. ¿El Imperio hace que registren más cagadas? Cagadas reales por día antes y después de la primera sesión.
--     Antes: hasta 14 días previos (menos si la cuenta es más nueva). Después: hasta 14 días (mínimo 3 cumplidos).
--     Es correlación: comparar con la línea base de abajo (gente que nunca abrió el Imperio, mismas fechas).
-- =====================================================================================================
with p as (select 'precio_crecimiento'::text as clave),
jug as (
  select e.user_id, min(e.creado) as t0 from public.imperio_eventos e where e.evento = 'sesion_inicio' group by e.user_id
),
v as (
  select j.user_id, j.t0, coalesce(a.variante, '(sin)') as variante,
         least(14, extract(epoch from j.t0 - pr.created_at) / 86400) as dias_antes,
         least(14, extract(epoch from now() - j.t0) / 86400) as dias_despues
  from jug j join public.profiles pr on pr.id = j.user_id
  left join public.imperio_asignaciones a on a.user_id = j.user_id and a.clave = (select clave from p)
),
r as (
  select v.*,
         (select count(*) from public.cagadas c where c.user_id = v.user_id
            and c.created_at >= v.t0 - make_interval(secs => v.dias_antes * 86400) and c.created_at < v.t0) / nullif(v.dias_antes, 0) as antes_dia,
         (select count(*) from public.cagadas c where c.user_id = v.user_id
            and c.created_at >= v.t0 and c.created_at < v.t0 + make_interval(secs => v.dias_despues * 86400)) / v.dias_despues as despues_dia
  from v where v.dias_despues >= 3 and v.dias_antes >= 1
)
select variante, count(*) as jugadores,
       round(avg(antes_dia)::numeric, 3) as cagadas_dia_antes, round(avg(despues_dia)::numeric, 3) as cagadas_dia_despues,
       round(100.0 * avg((despues_dia > antes_dia)::int), 1) as subieron_pct,
       round(100.0 * avg((despues_dia < antes_dia)::int), 1) as bajaron_pct
from r group by variante order by variante;

-- Línea base: usuarios que nunca abrieron el Imperio. Cagadas por día en los últimos 14 días contra los 14 anteriores.
with nunca as (
  select pr.id as user_id from public.profiles pr
  where pr.created_at < now() - interval '28 days'
    and not exists (select 1 from public.imperio_eventos e where e.user_id = pr.id)
    and exists (select 1 from public.cagadas c where c.user_id = pr.id and c.created_at > now() - interval '28 days')
)
select count(*) as usuarios,
       round(avg((select count(*) from public.cagadas c where c.user_id = n.user_id
                   and c.created_at between now() - interval '28 days' and now() - interval '14 days') / 14.0), 3) as cagadas_dia_antes,
       round(avg((select count(*) from public.cagadas c where c.user_id = n.user_id
                   and c.created_at > now() - interval '14 days') / 14.0), 3) as cagadas_dia_despues
from nunca n;


-- =====================================================================================================
-- 14. Reparto de variantes (para ver que los pesos salen como se pidió)
-- =====================================================================================================
select a.clave, a.variante, count(*) as usuarios, min(a.desde) as primera, max(a.desde) as ultima,
       round(100.0 * count(*) / sum(count(*)) over (partition by a.clave), 1) as pct
from public.imperio_asignaciones a group by 1, 2 order by 1, 2;

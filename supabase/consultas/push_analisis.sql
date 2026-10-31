-- Análisis de push (tabla push_envios). Correr a mano en el editor SQL.
-- tocado    = tocó el push (RPC push_tocado).
-- abrio_app = no tocó el push pero abrió la app dentro de 6 h (RPC push_abri_app).
-- Solo cuentan los envíos ok (los fallidos son tokens muertos).

-- 1. Tasa de apertura por tipo / subtipo / variante (últimos 30 días)
select tipo, subtipo, variante,
       count(*) as enviados,
       count(tocado) as tocados,
       count(abrio_app) as abrio_sin_tocar,
       round(100.0 * count(tocado) / nullif(count(*), 0), 1) as pct_toque,
       round(100.0 * (count(tocado) + count(abrio_app)) / nullif(count(*), 0), 1) as pct_volvio
  from public.push_envios
 where ok and enviado > now() - interval '30 days'
 group by 1, 2, 3
 order by 1, 2, 3;

-- 2. Tiempo hasta el toque (minutos), percentiles por tipo / subtipo
select tipo, subtipo,
       count(*) as tocados,
       round((percentile_cont(0.5) within group (order by extract(epoch from tocado - enviado)) / 60)::numeric, 1) as p50_min,
       round((percentile_cont(0.9) within group (order by extract(epoch from tocado - enviado)) / 60)::numeric, 1) as p90_min,
       round((max(extract(epoch from tocado - enviado)) / 60)::numeric, 1) as max_min
  from public.push_envios
 where ok and tocado is not null and enviado > now() - interval '30 days'
 group by 1, 2
 order by 1, 2;

-- 3. Ganador A/B de la poceta por subtipo.
-- Compara cada variante contra el resto del mismo subtipo (prueba z de dos proporciones).
-- |z| >= 1.96 = diferencia real al 95 %. Con menos de ~100 envíos por variante, no concluir.
with v as (
  select subtipo, variante, count(*)::numeric as n, count(tocado)::numeric as t
    from public.push_envios
   where ok and tipo = 'poceta' and enviado > now() - interval '30 days'
   group by 1, 2
),
s as (
  select subtipo, sum(n) as n_tot, sum(t) as t_tot from v group by 1
)
select v.subtipo, v.variante, v.n as enviados, v.t as tocados,
       round(100 * v.t / nullif(v.n, 0), 1) as pct,
       round(100 * (s.t_tot - v.t) / nullif(s.n_tot - v.n, 0), 1) as pct_resto,
       round((
         (v.t / nullif(v.n, 0) - (s.t_tot - v.t) / nullif(s.n_tot - v.n, 0))
         / nullif(sqrt((s.t_tot / s.n_tot) * (1 - s.t_tot / s.n_tot) * (1 / v.n + 1 / nullif(s.n_tot - v.n, 0))), 0)
       )::numeric, 2) as z
  from v join s using (subtipo)
 order by v.subtipo, pct desc;

-- 4. Rendimiento por hora local de envío (poceta), con la zona del último token del usuario
with z as (
  select distinct on (user_id) user_id, zona
    from public.push_tokens
   where user_id is not null
   order by user_id, updated_at desc
)
select extract(hour from e.enviado at time zone coalesce(z.zona, 'America/Caracas'))::int as hora_local,
       count(*) as enviados,
       round(100.0 * count(e.tocado) / nullif(count(*), 0), 1) as pct_toque
  from public.push_envios e
  left join z on z.user_id = e.user_id
 where e.ok and e.tipo = 'poceta' and e.enviado > now() - interval '30 days'
 group by 1
 order by 1;

-- 5. Volumen diario y fallidos (todos los tipos)
select date_trunc('day', enviado)::date as dia, tipo,
       count(*) filter (where ok) as ok, count(*) filter (where not ok) as fallidos
  from public.push_envios
 where enviado > now() - interval '14 days'
 group by 1, 2
 order by 1 desc, 2;

-- 6. ¿La poceta hace que la gente se desactive? Opt-outs actuales
select count(*) filter (where not poceta) as apagados, count(*) as con_ajustes
  from public.push_ajustes;

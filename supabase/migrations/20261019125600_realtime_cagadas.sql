-- La app escucha inserts/deletes para refrescar ranking y calendario sin pull-to-refresh.
alter publication supabase_realtime add table public.cagadas;

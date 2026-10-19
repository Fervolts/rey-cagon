-- Build de la app en ese teléfono: el push de "hay versión nueva" solo va a quien tiene una más vieja
-- (y que ya sabe actualizarse sola). Null = versión anterior a 1.8.2, que no lo reporta.
alter table public.push_tokens add column app_build int;

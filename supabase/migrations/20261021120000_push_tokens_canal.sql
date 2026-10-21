-- De qué canal es cada teléfono: la versión de Play se actualiza por la tienda y no debe recibir
-- el aviso de versión nueva de la APK directa. null = instalación vieja que aún no lo reporta.
alter table public.push_tokens add column canal text check (canal in ('play', 'directo'));

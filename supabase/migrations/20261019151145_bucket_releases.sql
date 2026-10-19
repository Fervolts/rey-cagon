-- APKs y version.json para el actualizador dentro de la app. Público para leer; solo se sube con la service key (scripts/publicar.sh).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('releases', 'releases', true, 104857600,
        array['application/vnd.android.package-archive', 'application/json'])
on conflict (id) do nothing;

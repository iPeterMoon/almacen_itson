-- 20261112000013_privilegios_api.sql

-- Lectura para la API; RLS sigue limitando las filas
grant select on all tables in schema public to authenticated;

-- Escrituras directas que las políticas RLS permiten
grant insert, update on public.categorias to authenticated;
grant insert on public.unidades_medida to authenticated;
grant insert, update on public.productos to authenticated;
grant insert, update on public.presentaciones_producto to authenticated;
grant insert on public.almacenes to authenticated;
grant insert, update on public.trabajadores to authenticated;
grant insert, update on public.zonas to authenticated;
grant insert, update, delete on public.limites_material_zona to authenticated;
grant insert, update, delete on public.trabajadores_zonas to authenticated;
grant update (leida_en) on public.notificaciones to authenticated;

-- Secuencias para inserts directos
grant usage, select on all sequences in schema public to authenticated;

-- service_role para tareas administrativas
grant all privileges on all tables in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;

-- Futuras tablas y secuencias
alter default privileges in schema public
  grant select on tables to authenticated;
alter default privileges in schema public
  grant usage, select on sequences to authenticated;
alter default privileges in schema public
  grant all on tables to service_role;
alter default privileges in schema public
  grant all on sequences to service_role;
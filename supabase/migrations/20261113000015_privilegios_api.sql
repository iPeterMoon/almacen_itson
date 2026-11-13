-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 13: privilegios de la API
-- La API consulta con el token del usuario (rol authenticated). Las
-- migraciones crean las tablas y las políticas RLS, pero Supabase ya no
-- otorga permisos de tabla automáticamente a authenticated; sin estos
-- GRANT, PostgREST responde "permission denied" antes de evaluar RLS.
--
-- Se otorga SELECT a todas las tablas y vistas porque RLS sigue
-- limitando las filas. Las escrituras directas se otorgan solo donde
-- existe una política que las permita; el resto se escribe con RPC
-- security definer.
-- =====================================================================

grant select on all tables in schema public to authenticated;

-- Escrituras directas permitidas por las políticas RLS
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

-- Las tablas con identity necesitan la secuencia para insertar
grant usage, select on all sequences in schema public to authenticated;

-- service_role se usa solo en tareas administrativas (no en la API)
grant all privileges on all tables in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;

-- Que las próximas tablas y secuencias no vuelvan a quedar sin permisos
alter default privileges in schema public
  grant select on tables to authenticated;
alter default privileges in schema public
  grant usage, select on sequences to authenticated;
alter default privileges in schema public
  grant all on tables to service_role;
alter default privileges in schema public
  grant all on sequences to service_role;

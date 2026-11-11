-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 11: campus y almacenes reales
-- Datos confirmados por el equipo; se cargan en todos los ambientes.
--   * Campus Guaymas y Navojoa, uno por unidad, con el mismo nombre.
--   * Almacenes de Náinari: Principal y Dormitorios.
-- Los almacenes de Centro, Guaymas y Navojoa aún no se conocen; los de
-- Centro para desarrollo local siguen en supabase/seed.sql.
-- =====================================================================

insert into public.campus (unidad_id, nombre, clave)
select u.id, c.nombre, c.clave
  from (values ('Guaymas', 'GUA'), ('Navojoa', 'NAV')) as c(nombre, clave)
  join public.unidades u on u.nombre = c.nombre
on conflict do nothing;

insert into public.almacenes (campus_id, nombre)
select c.id, a.nombre
  from (values ('Principal'), ('Dormitorios')) as a(nombre)
  cross join public.campus c
 where c.clave = 'NAI'
on conflict do nothing;

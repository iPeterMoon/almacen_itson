-- Datos de ejemplo para desarrollo local (supabase db reset los carga).
-- Los almacenes reales confirmados (Náinari: Principal y Dormitorios) van en
-- la migración 11. Los nombres de Centro son de ejemplo hasta que el equipo los confirme.
insert into public.almacenes (campus_id, nombre)
select c.id, a.nombre
  from (values ('CEN', 'Almacén 1'), ('CEN', 'Almacén 2'), ('CEN', 'Almacén 3')) as a(clave, nombre)
  join public.campus c on c.clave = a.clave;

-- Datos de ejemplo para desarrollo local (supabase db reset los carga).
-- Los almacenes reales y sus nombres los confirma el equipo.
insert into public.almacenes (campus_id, nombre)
select c.id, a.nombre
  from (values ('CEN', 'Almacén 1'), ('CEN', 'Almacén 2'), ('CEN', 'Almacén 3'),
               ('NAI', 'Principal'), ('NAI', 'Dormitorios')) as a(clave, nombre)
  join public.campus c on c.clave = a.clave;

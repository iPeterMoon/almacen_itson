-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 4: catálogos iniciales
-- Datos que el sistema necesita para funcionar en cualquier ambiente.
-- Los almacenes y usuarios de prueba van en supabase/seed.sql.
-- =====================================================================

insert into public.unidades (nombre) values ('Obregón'), ('Guaymas'), ('Navojoa');

insert into public.campus (unidad_id, nombre, clave)
select u.id, c.nombre, c.clave
  from (values ('Náinari', 'NAI'), ('Centro', 'CEN')) as c(nombre, clave)
  join public.unidades u on u.nombre = 'Obregón';

insert into public.categorias (nombre) values ('Líquido'), ('Papel'), ('Bolsas');

insert into public.unidades_medida (clave, nombre) values
  ('L', 'Litro'), ('ml', 'Mililitro'), ('pza', 'Pieza'), ('caja', 'Caja'), ('rollo', 'Rollo');

-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 20: detalle de una boleta
-- HU11 (AI-70): todo lo que muestra el detalle de una boleta en el historial.
--
-- Una fila por boleta, con los materiales y las herramientas como JSON:
--   materiales:   código, concepto, almacén (de donde se descontó), presentación, cantidad
--   herramientas: código, nombre, modelo, número de serie y estado ACTUAL del activo
-- El almacén sale de los movimientos de SALIDA de cada renglón; si un renglón salió de
-- más de un almacén se listan separados por coma. autorizo_nombre es null si no hubo
-- autorización (el sistema solo guarda el nombre que capturó el almacenista).
--
-- Consulta típica (la API la usa con el id de la boleta):
--   select * from vista_detalle_boleta where boleta_id = 9
--
-- security_invoker: la vista se lee con los permisos de quien consulta, así que la RLS
-- de boletas limita el resultado a los campus del usuario (una boleta de otro campus
-- simplemente no aparece).
-- =====================================================================

create or replace view public.vista_detalle_boleta
with (security_invoker = true) as
select b.id                  as boleta_id,
       b.folio,
       b.campus_id,
       c.nombre              as campus,
       b.entregado_en,
       ent.nombre            as entregado_por,
       b.trabajador_id,
       b.solicitante_nombre,
       t.dependencia,
       b.solicitante_unidad  as unidad,
       b.autorizo_nombre,
       coalesce((
         select jsonb_agg(
                  jsonb_build_object(
                    'codigo',       p.codigo,
                    'concepto',     p.nombre_estandar,
                    'almacen',      (select string_agg(distinct al.nombre, ', ' order by al.nombre)
                                       from movimientos_inventario mi
                                       join ubicaciones u  on u.id  = mi.ubicacion_id
                                       join almacenes   al on al.id = u.almacen_id
                                      where mi.boleta_material_id = bm.id
                                        and mi.tipo = 'SALIDA'),
                    'presentacion', pr.nombre,
                    'cantidad',     bm.cantidad)
                  order by bm.id)
           from boletas_materiales bm
           join productos p on p.id = bm.producto_id
           left join presentaciones_producto pr on pr.id = bm.presentacion_id
          where bm.boleta_id = b.id), '[]'::jsonb) as materiales,
       coalesce((
         select jsonb_agg(
                  jsonb_build_object(
                    'codigo',       a.codigo,
                    'nombre',       a.nombre,
                    'modelo',       a.modelo,
                    'numero_serie', a.numero_serie,
                    'estado',       a.estado)
                  order by bh.id)
           from boletas_herramientas bh
           join activos a on a.id = bh.activo_id
          where bh.boleta_id = b.id), '[]'::jsonb) as herramientas
  from boletas b
  join campus c on c.id = b.campus_id
  left join trabajadores t on t.id = b.trabajador_id
  left join usuarios ent on ent.id = b.entregado_por;

comment on view public.vista_detalle_boleta is
  'HU11 (AI-70): detalle de una boleta con materiales (y su almacén), herramientas (con su estado actual) y quién autorizó. La RLS de boletas limita a los campus del usuario.';

-- Buscar de dónde salió cada renglón recorre los movimientos por boleta_material_id,
-- que no tenía índice.
create index if not exists movimientos_inventario_boleta_material_ix
  on public.movimientos_inventario (boleta_material_id)
  where boleta_material_id is not null;

-- Solo lectura y solo para usuarios con sesión
revoke all on public.vista_detalle_boleta from anon;
revoke insert, update, delete, truncate, references, trigger on public.vista_detalle_boleta from authenticated;
grant select on public.vista_detalle_boleta to authenticated;
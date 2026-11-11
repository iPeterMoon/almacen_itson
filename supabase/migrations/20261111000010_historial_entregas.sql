-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 10: historial de entregas
-- Módulos: 2 Ventanilla y Entregas (dueño de los datos) y 4 Reportes.
-- HU6: consultar lo entregado en ventanilla por solicitante, por insumo
-- y por zona (AI-39).
--
-- Una fila por material entregado. Solo cuenta lo que realmente salió:
-- boletas ENTREGADA (las pendientes, autorizadas sin entregar o
-- rechazadas no descontaron existencia). Los préstamos de herramientas
-- tienen su propio historial en vista_seguimiento_prestamos.
--
-- Consultas típicas (la API agrega paginación y orden por entregado_en):
--   por solicitante registrado:  where trabajador_id = 15
--   por solicitante sin registro: where solicitante_nombre ilike '%rosa%'
--   por insumo:                  where producto_id = 7
--   por zona:                    where zona_id = 3
--   por periodo:                 where entregado_en between ... and ...
--
-- security_invoker: la vista se lee con los permisos de quien consulta,
-- así que la RLS de boletas limita el resultado a los campus del usuario.
-- =====================================================================

create or replace view public.vista_historial_entregas
with (security_invoker = true) as
select bm.id                 as boleta_material_id,
       b.id                  as boleta_id,
       b.folio,
       b.campus_id,
       c.nombre              as campus,
       b.entregado_en,
       ent.nombre            as entregado_por,
       -- Solicitante (HU6 E2: registrado o sin registro)
       b.trabajador_id,
       b.solicitante_nombre,
       case when b.trabajador_id is null then 'SIN_REGISTRO' else 'REGISTRADO' end as tipo_solicitante,
       t.tipo                as tipo_trabajador,
       t.compania,
       t.dependencia,
       b.solicitante_unidad,
       b.numero_solicitud,
       -- Zona (HU6 E10)
       b.zona_id,
       z.nombre              as zona,
       z.edificio,
       z.piso,
       -- Insumo
       bm.producto_id,
       p.codigo,
       p.nombre_estandar,
       p.alias,
       p.tipo                as tipo_producto,
       pr.nombre             as presentacion,
       bm.cantidad,
       bm.cantidad_base,
       um.clave              as unidad_base,
       bm.comentario,
       -- Excepciones autorizadas (HU6 E8 y E10)
       bm.excede_periodicidad,
       bm.excede_limite,
       bm.motivo_excepcion,
       -- Sobrantes devueltos (HU4)
       coalesce((select sum(e.cantidad_base) from entradas e
                  where e.boleta_material_id = bm.id), 0)::numeric(12,3) as cantidad_reingresada
  from boletas b
  join boletas_materiales bm on bm.boleta_id = b.id
  join campus c on c.id = b.campus_id
  join productos p on p.id = bm.producto_id
  join unidades_medida um on um.id = p.unidad_base_id
  left join presentaciones_producto pr on pr.id = bm.presentacion_id
  left join trabajadores t on t.id = b.trabajador_id
  left join zonas z on z.id = b.zona_id
  left join usuarios ent on ent.id = b.entregado_por
 where b.estado = 'ENTREGADA';

comment on view public.vista_historial_entregas is
  'HU6 (AI-39): historial de material entregado en ventanilla, una fila por renglón de boleta entregada. Se filtra por solicitante, insumo, zona y periodo; la RLS de boletas limita a los campus del usuario.';

-- Índices para los filtros. Ya existen:
--   boletas_trabajador_ix (trabajador_id, entregado_en desc)  -> por solicitante
--   boletas_zona_ix       (zona_id, entregado_en desc)        -> por zona
--   boletas_materiales_producto_ix (producto_id)              -> por insumo
-- Faltan el listado general por campus y periodo, y la búsqueda parcial
-- por nombre de solicitantes sin registro.
create index boletas_entregadas_campus_ix on public.boletas (campus_id, entregado_en desc)
  where estado = 'ENTREGADA';
create index boletas_solicitante_nombre_trgm on public.boletas
  using gin (solicitante_nombre extensions.gin_trgm_ops);

-- Solo lectura y solo para usuarios con sesión
revoke all on public.vista_historial_entregas from anon;
revoke insert, update, delete, truncate, references, trigger on public.vista_historial_entregas from authenticated;
grant select on public.vista_historial_entregas to authenticated;

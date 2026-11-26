-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 23: búsqueda por fecha del historial
-- Módulo: 3 Ventanilla. HU11.
--
-- buscar_boletas agrega un rango de fechas inclusivo sobre entregado_en, en
-- días calendario de Hermosillo (la misma fecha que muestra la tabla). Se
-- combina con la búsqueda por solicitante o folio.
--
--   select * from buscar_boletas(null, 8, 0, '2026-11-01', '2026-11-30')
-- =====================================================================

-- La firma anterior queda obsoleta: se elimina para no dejar dos versiones
-- que PostgREST no sabría resolver cuando solo se mandan tres argumentos.
drop function if exists public.buscar_boletas(text, int, int);

-- Acelera el filtro por fecha. El índice del orden (creado_en desc, id desc)
-- sigue siendo el que resuelve el historial sin fechas.
create index if not exists boletas_entregado_en_ix
  on public.boletas (entregado_en desc)
  where entregado_en is not null;

create function public.buscar_boletas(
  p_texto     text default null,
  p_limite    int  default 50,
  p_desplazar int  default 0,
  p_desde     date default null,
  p_hasta     date default null)
returns table (
  boleta_id bigint, folio text, solicitante_nombre text, dependencia text,
  campus text, entregado_en timestamptz, autorizo_nombre text,
  total_resultados bigint)
language sql stable security invoker set search_path = public as $$
  select b.id, b.folio, b.solicitante_nombre,
         -- Registrado: la dependencia del trabajador. Sin registro: la unidad capturada.
         coalesce(t.dependencia, b.solicitante_unidad),
         c.nombre, b.entregado_en, b.autorizo_nombre,
         count(*) over ()
    from boletas b
    join campus c on c.id = b.campus_id
    left join trabajadores t on t.id = b.trabajador_id
   where (nullif(btrim(p_texto), '') is null
          or sin_acentos(b.folio) like '%' || sin_acentos(btrim(p_texto)) || '%'
          or sin_acentos(b.solicitante_nombre) like '%' || sin_acentos(btrim(p_texto)) || '%')
     -- El día completo: desde la medianoche y antes de la medianoche del día
     -- siguiente, ambos en horario de Hermosillo.
     and (p_desde is null
          or b.entregado_en >= (p_desde::timestamp at time zone 'America/Hermosillo'))
     and (p_hasta is null
          or b.entregado_en < ((p_hasta + 1)::timestamp at time zone 'America/Hermosillo'))
   order by b.creado_en desc, b.id desc
   limit p_limite offset p_desplazar
$$;

comment on function public.buscar_boletas(text, int, int, date, date) is
  'HU11: historial de boletas paginado; busca por solicitante o folio y por rango de fechas de entrega (inclusivo, Hermosillo).';

revoke execute on function public.buscar_boletas(text, int, int, date, date) from public, anon;
grant execute on function public.buscar_boletas(text, int, int, date, date) to authenticated;

-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 21: búsqueda del historial de boletas
-- Módulo: 3 Ventanilla.
-- HU11 (AI-69): el historial muestra una fila por boleta y se busca por
-- solicitante o folio sin distinguir mayúsculas ni acentos ("jose" encuentra
-- "José Pérez"; "bol-2026-0007" encuentra "BOL-2026-0007").
--
-- buscar_boletas devuelve la página pedida, de la boleta más reciente a la más
-- antigua, y en cada fila el total de boletas que cumplen la búsqueda
-- (count(*) over (), igual que buscar_productos), para que el paginador no
-- necesite una segunda consulta. Es security invoker: la RLS de boletas limita
-- el resultado a los campus del usuario.
--
-- Consulta típica (la API la usa con la búsqueda y la página):
--   select * from buscar_boletas('jose', 8, 0)
-- =====================================================================

-- unaccent quita los acentos ("José" -> "Jose"). Supabase instala las
-- extensiones en el schema extensions.
create extension if not exists unaccent with schema extensions;

-- unaccent() no es immutable (depende del diccionario que se use), así que no
-- se puede usar en un índice. Este envoltorio fija el diccionario y además pasa
-- a minúsculas, para comparar texto sin importar acentos ni mayúsculas.
create function public.sin_acentos(p_texto text)
returns text
language sql immutable strict parallel safe set search_path = '' as $$
  select pg_catalog.lower(extensions.unaccent('extensions.unaccent'::regdictionary, p_texto))
$$;

-- Índices de la búsqueda: trigramas sobre el texto sin acentos, para que
-- "contiene" (like '%texto%') no tenga que revisar boleta por boleta.
create index boletas_folio_busqueda_ix
  on public.boletas using gin (public.sin_acentos(folio) extensions.gin_trgm_ops);
create index boletas_solicitante_busqueda_ix
  on public.boletas using gin (public.sin_acentos(solicitante_nombre) extensions.gin_trgm_ops);

-- Índice del orden del historial: de la más reciente a la más antigua.
create index boletas_recientes_ix on public.boletas (creado_en desc, id desc);

create function public.buscar_boletas(
  p_texto     text default null,
  p_limite    int  default 50,
  p_desplazar int  default 0)
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
   where nullif(btrim(p_texto), '') is null
      or sin_acentos(b.folio) like '%' || sin_acentos(btrim(p_texto)) || '%'
      or sin_acentos(b.solicitante_nombre) like '%' || sin_acentos(btrim(p_texto)) || '%'
   order by b.creado_en desc, b.id desc
   limit p_limite offset p_desplazar
$$;

revoke execute on function public.buscar_boletas(text, int, int) from public, anon;
grant execute on function public.buscar_boletas(text, int, int) to authenticated;

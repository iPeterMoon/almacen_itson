-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 21: importar entregas anteriores
-- HU11. El Excel se valida en el servidor; aquí se valida lo que solo la
-- base sabe (folios existentes, códigos de material y almacenes del campus)
-- y se inserta todo en una sola transacción.
--
-- Las entregas importadas son históricas: NO generan movimientos de
-- inventario (no descuentan el stock actual). La plantilla de la HU trae
-- solo materiales; no se importan herramientas ni se crean préstamos.
-- =====================================================================

-- El renglón conserva el almacén del que salió el material. Las entregas
-- normales siguen derivándolo de movimientos_inventario; este campo es el
-- fallback de las importadas, que no crean movimientos.
alter table public.boletas_materiales
  add column almacen_id bigint references public.almacenes(id);

comment on column public.boletas_materiales.almacen_id is
  'Almacén declarado al importar una entrega anterior (HU11). Null en entregas normales: ahí el almacén se obtiene de los movimientos de SALIDA.';

-- La misma vista de la migración 20, con el almacén importado como fallback.
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
                    'almacen',      coalesce(
                                      (select string_agg(distinct al.nombre, ', ' order by al.nombre)
                                         from movimientos_inventario mi
                                         join ubicaciones u  on u.id  = mi.ubicacion_id
                                         join almacenes   al on al.id = u.almacen_id
                                        where mi.boleta_material_id = bm.id
                                          and mi.tipo = 'SALIDA'),
                                      (select al.nombre from almacenes al where al.id = bm.almacen_id)),
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

-- ---------------------------------------------------------------------
-- importar_entregas: valida todo antes de insertar. Devuelve siempre
-- { importadas, errores: [{ fila, motivo }] }; si hay errores, importadas
-- es 0 y no se escribió ninguna fila.
-- ---------------------------------------------------------------------
create or replace function public.importar_entregas(
  p_boletas jsonb,
  p_campus_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, privado
as $$
declare
  v_campus         bigint;
  v_errores        jsonb := '[]'::jsonb;
  v_b              jsonb;
  v_r              jsonb;
  v_fila           bigint;
  v_folio          text;
  v_fecha_texto    text;
  v_fecha          timestamptz;
  v_almacen_nombre text;
  v_almacen_id     bigint;
  v_producto_id    bigint;
  v_codigo         text;
  v_cantidad       numeric;
  v_folios         text[] := '{}';
  v_boleta_id      bigint;
  v_firma          text;
  v_importadas     int := 0;
begin
  -- El campus del token, o el que pide el servidor si el usuario tiene varios.
  if p_campus_id is null then
    select campus_id into v_campus
      from usuarios where id = auth.uid() and activo limit 1;
  else
    v_campus := p_campus_id;
  end if;

  if coalesce(mi_rol(), '') not in ('ALMACENISTA', 'SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN')
     or v_campus is null or v_campus not in (select mis_campus()) then
    raise exception 'SIN_PERMISO: No puedes importar entregas en ese campus.';
  end if;

  if p_boletas is null or jsonb_typeof(p_boletas) <> 'array'
     or jsonb_array_length(p_boletas) = 0 then
    raise exception 'IMPORTACION_VACIA: El archivo no tiene boletas para importar.';
  end if;
  if jsonb_array_length(p_boletas) > 1000 then
    raise exception 'IMPORTACION_EXCESIVA: El archivo supera el máximo de boletas.';
  end if;

  -- ---------------------- validación de todo el archivo ----------------------
  for v_b in select value from jsonb_array_elements(p_boletas) loop
    begin
      v_fila := (v_b->>'fila')::bigint;
    exception when others then
      v_fila := 1;
    end;
    if v_fila is null or v_fila < 2 then
      v_fila := 1;
    end if;

    v_folio := btrim(coalesce(v_b->>'folio', ''));
    if v_folio = '' then
      v_errores := v_errores || jsonb_build_array(
        jsonb_build_object('fila', v_fila, 'motivo', 'El folio es obligatorio.'));
    elsif v_folio = any(v_folios) then
      v_errores := v_errores || jsonb_build_array(
        jsonb_build_object('fila', v_fila, 'motivo', 'El folio ' || v_folio || ' está repetido en el archivo.'));
    elsif exists (select 1 from boletas where folio = v_folio) then
      v_errores := v_errores || jsonb_build_array(
        jsonb_build_object('fila', v_fila, 'motivo', 'El folio ' || v_folio || ' ya existe.'));
    end if;
    v_folios := v_folios || v_folio;

    v_fecha_texto := btrim(coalesce(v_b->>'fecha', ''));
    if v_fecha_texto !~ '^\d{4}-\d{2}-\d{2}$' then
      v_errores := v_errores || jsonb_build_array(
        jsonb_build_object('fila', v_fila, 'motivo', 'La fecha debe estar en formato AAAA-MM-DD.'));
      v_fecha := null;
    else
      begin
        v_fecha := v_fecha_texto::date::timestamptz;
      exception when others then
        v_fecha := null;
      end;
      if v_fecha is null then
        v_errores := v_errores || jsonb_build_array(
          jsonb_build_object('fila', v_fila, 'motivo', 'La fecha no es válida.'));
      end if;
    end if;

    if btrim(coalesce(v_b->>'solicitante', '')) = '' then
      v_errores := v_errores || jsonb_build_array(
        jsonb_build_object('fila', v_fila, 'motivo', 'El solicitante es obligatorio.'));
    end if;
    if btrim(coalesce(v_b->>'dependencia', '')) = '' then
      v_errores := v_errores || jsonb_build_array(
        jsonb_build_object('fila', v_fila, 'motivo', 'La dependencia es obligatoria.'));
    end if;

    v_almacen_nombre := btrim(coalesce(v_b->>'almacen', ''));
    select id into v_almacen_id
      from almacenes
     where campus_id = v_campus
       and activo
       and lower(btrim(nombre)) = lower(v_almacen_nombre);
    if v_almacen_id is null then
      v_errores := v_errores || jsonb_build_array(
        jsonb_build_object('fila', v_fila,
          'motivo', 'El almacén "' || v_almacen_nombre || '" no existe en el campus.'));
    end if;

    -- Materiales
    for v_r in select value from jsonb_array_elements(coalesce(v_b->'materiales', '[]'::jsonb)) loop
      v_codigo := btrim(coalesce(v_r->>'codigo', ''));
      if v_codigo = '' then
        v_errores := v_errores || jsonb_build_array(
          jsonb_build_object('fila', coalesce((v_r->>'fila')::bigint, v_fila),
            'motivo', 'El código de material es obligatorio.'));
      else
        select id into v_producto_id
          from productos
         where activo and upper(btrim(codigo)) = upper(v_codigo);
        if v_producto_id is null then
          v_errores := v_errores || jsonb_build_array(
            jsonb_build_object('fila', coalesce((v_r->>'fila')::bigint, v_fila),
              'motivo', 'El código de material ' || v_codigo || ' no existe.'));
        end if;
      end if;

      v_cantidad := null;
      begin
        v_cantidad := (v_r->>'cantidad')::numeric;
      exception when others then
        v_cantidad := null;
      end;
      if v_cantidad is null or v_cantidad <= 0 then
        v_errores := v_errores || jsonb_build_array(
          jsonb_build_object('fila', coalesce((v_r->>'fila')::bigint, v_fila),
            'motivo', 'La cantidad debe ser un número mayor a cero.'));
      end if;
    end loop;
  end loop;

  -- Todo o nada: si algo falló, no se inserta ninguna boleta.
  if jsonb_array_length(v_errores) > 0 then
    return jsonb_build_object('importadas', 0, 'errores', v_errores);
  end if;

  -- ------------------------------ inserciones ------------------------------
  -- Una entrega histórica no trae firmas, pero boletas_entregada_ck y el
  -- trigger validar_firma exigen dos rutas del campus que existan en Storage.
  -- Se usa un marcador reutilizable por campus (no una firma falsa de nadie).
  v_firma := v_campus::text || '/importacion/sin-firma-importada.png';
  insert into storage.objects (bucket_id, name, metadata)
  select 'firmas', v_firma, jsonb_build_object('importacion', true)
   where not exists (select 1 from storage.objects
                      where bucket_id = 'firmas' and name = v_firma);

  for v_b in select value from jsonb_array_elements(p_boletas) loop
    v_folio := btrim(v_b->>'folio');
    v_fecha := (v_b->>'fecha')::date::timestamptz;
    select id into v_almacen_id
      from almacenes
     where campus_id = v_campus and activo
       and lower(btrim(nombre)) = lower(btrim(v_b->>'almacen'));

    insert into boletas (folio, campus_id, solicitante_nombre, solicitante_unidad,
                         estado, firma_recibe_path, firma_entrega_path,
                         entregado_en, creado_en, entregado_por)
    values (v_folio, v_campus, btrim(v_b->>'solicitante'), btrim(v_b->>'dependencia'),
            'ENTREGADA', v_firma, v_firma,
            v_fecha, v_fecha, auth.uid())
    returning id into v_boleta_id;

    for v_r in select value from jsonb_array_elements(coalesce(v_b->'materiales', '[]'::jsonb)) loop
      select id into v_producto_id
        from productos
       where activo and upper(btrim(codigo)) = upper(btrim(v_r->>'codigo'));
      insert into boletas_materiales (boleta_id, producto_id, almacen_id, cantidad, cantidad_base)
      values (v_boleta_id, v_producto_id, v_almacen_id,
              (v_r->>'cantidad')::numeric, (v_r->>'cantidad')::numeric);
    end loop;

    v_importadas := v_importadas + 1;
  end loop;

  return jsonb_build_object('importadas', v_importadas, 'errores', '[]'::jsonb);
end $$;

comment on function public.importar_entregas(jsonb, bigint) is
  'HU11: importa entregas anteriores (solo materiales). Valida todo antes de insertar; devuelve { importadas, errores: [{ fila, motivo }] }.';

revoke execute on function public.importar_entregas(jsonb, bigint) from public, anon;
grant execute on function public.importar_entregas(jsonb, bigint) to authenticated;

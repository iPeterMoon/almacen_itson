-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 24: fecha de las entregas importadas
-- HU11. importar_entregas guardaba la fecha del Excel como medianoche en la
-- zona horaria de la sesión, que en Supabase es UTC: "2025-03-04" quedaba en
-- 2025-03-04T00:00Z, que en Hermosillo (UTC-7) es el 3 de marzo a las 17:00.
-- El historial y su filtro de fechas cuentan los días en Hermosillo, así que
-- la entrega aparecía un día antes y el filtro desde/hasta no la encontraba.
-- Ahora la fecha es la medianoche de Hermosillo, igual que en buscar_boletas.
-- Solo cambia esa expresión; el resto de la función es el de la migración 21.
-- Las boletas ya importadas con la fecha corrida no se modifican aquí.
-- =====================================================================

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
  -- Las firmas se dejan null: la boleta está marcada como importada, así que
  -- boletas_entregada_ck la acepta y el trigger no valida rutas inexistentes.
  for v_b in select value from jsonb_array_elements(p_boletas) loop
    v_folio := btrim(v_b->>'folio');
    v_fecha := (v_b->>'fecha')::date::timestamp at time zone 'America/Hermosillo';
    select id into v_almacen_id
      from almacenes
     where campus_id = v_campus and activo
       and lower(btrim(nombre)) = lower(btrim(v_b->>'almacen'));

    insert into boletas (folio, campus_id, solicitante_nombre, solicitante_unidad,
                         estado, importada, entregado_en, creado_en, entregado_por)
    values (v_folio, v_campus, btrim(v_b->>'solicitante'), btrim(v_b->>'dependencia'),
            'ENTREGADA', true, v_fecha, v_fecha, auth.uid())
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
-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 20: un solo préstamo por tipo
-- de herramienta (HU8)
-- Un trabajador no puede recibir una herramienta del mismo tipo que otra
-- que ya tiene prestada, ni dos del mismo tipo en la misma boleta. El tipo
-- es el nombre del activo sin distinguir mayúsculas ni espacios
-- ("Taladro" = " taladro"). crear_boleta lo rechaza. Parte de la
-- crear_boleta de la migración 19 (entregas sin autorizaciones).
-- =====================================================================

create or replace function privado.tipo_de_activo(p_nombre text)
returns text
language sql immutable set search_path = '' as $$
  select regexp_replace(lower(btrim(p_nombre)), '\s+', ' ', 'g')
$$;
comment on function privado.tipo_de_activo(text) is
  'Normaliza el nombre de un activo para compararlo como tipo de herramienta.';

-- Herramienta del mismo tipo que el trabajador ya tiene en un préstamo abierto.
-- Si se pasa p_boleta_id, primero devuelve la de esa boleta (dos del mismo tipo
-- en la boleta que se está creando, que aún no abre sus préstamos).
-- Sin coincidencia no devuelve filas.
create or replace function privado.herramienta_del_mismo_tipo(
  p_trabajador_id bigint, p_nombre text, p_boleta_id bigint default null)
returns table (boleta_id bigint, codigo text, prestamo text)
language sql stable set search_path = public, privado as $$
  select b.id, a.codigo, p.folio
    from boletas_herramientas bh
    join boletas b on b.id = bh.boleta_id
    join activos a on a.id = bh.activo_id
    left join prestamos p on p.boleta_herramienta_id = bh.id and p.estado = 'ACTIVO'
   where b.trabajador_id = p_trabajador_id
     and tipo_de_activo(a.nombre) = tipo_de_activo(p_nombre)
     and (p.id is not null or b.id = p_boleta_id)
   order by (b.id = p_boleta_id) desc nulls last
   limit 1
$$;

revoke execute on function privado.tipo_de_activo(text),
  privado.herramienta_del_mismo_tipo(bigint, text, bigint)
from public, anon, authenticated;

create or replace function public.crear_boleta(
  p_materiales          jsonb  default '[]'::jsonb,
  p_herramientas        jsonb  default '[]'::jsonb,
  p_trabajador_id         bigint default null,
  p_solicitante_nombre  text   default null,
  p_solicitante_unidad  text   default null,
  p_zona_id             bigint default null,
  p_numero_solicitud    text   default null,
  p_autorizo_nombre     text   default null,
  p_firma_recibe        text   default null,
  p_firma_entrega       text   default null,
  p_campus_id           bigint default null)
returns table (boleta_id bigint, folio text, estado text, alertas jsonb)
language plpgsql security definer set search_path = public, privado as $$
declare
  v_campus     bigint;
  v_nombre     text;
  v_zona       bigint := p_zona_id;
  v_trabajador        trabajadores%rowtype;
  v_id         bigint;
  v_folio      text;
  v_item       jsonb;
  v_prod       productos%rowtype;
  v_base       numeric;
  v_eval       record;
  v_motivo     text;
  v_alertas    jsonb := '[]'::jsonb;
  v_act        record;
  v_dias       int;
  v_vencido    boolean;
  v_custodio   text;
  v_prevista   timestamptz;
  v_previo     record;
begin
  v_campus := campus_de_operacion(p_campus_id);

  if jsonb_array_length(coalesce(p_materiales, '[]')) + jsonb_array_length(coalesce(p_herramientas, '[]')) = 0 then
    raise exception 'BOLETA_VACIA: Agrega al menos un material o una herramienta.';
  end if;

  if nullif(btrim(p_firma_recibe), '') is null or nullif(btrim(p_firma_entrega), '') is null then
    raise exception 'FIRMAS_REQUERIDAS: Deben firmar quien recibe y quien entrega.';
  end if;

  -- Solicitante (HU6 E2)
  if p_trabajador_id is not null then
    select * into v_trabajador from trabajadores where id = p_trabajador_id and activo;
    if v_trabajador.id is null then
      raise exception 'SOLICITANTE_NO_EXISTE: El solicitante no está en el registro de personal.';
    end if;
    v_nombre := v_trabajador.nombre;
    v_zona := zona_de_entrega(p_trabajador_id, p_zona_id);
    -- Dos boletas simultáneas del mismo trabajador se forman en fila para que
    -- la revisión de herramientas del mismo tipo vea el préstamo de la otra.
    if jsonb_array_length(coalesce(p_herramientas, '[]')) > 0 then
      perform 1 from trabajadores where id = p_trabajador_id for update;
    end if;
  else
    v_nombre := nullif(btrim(p_solicitante_nombre), '');
    if v_nombre is null or nullif(btrim(p_solicitante_unidad), '') is null then
      raise exception 'SOLICITANTE_REQUERIDO: Captura nombre y unidad o campus del solicitante no registrado.';
    end if;
    if jsonb_array_length(coalesce(p_herramientas, '[]')) > 0 then
      raise exception 'HERRAMIENTA_SIN_SOLICITANTE: Las herramientas solo se prestan a personal registrado.';
    end if;
  end if;

  v_folio := siguiente_folio('BOL');
  insert into boletas (folio, campus_id, solicitante_nombre, trabajador_id, solicitante_unidad, zona_id,
                          numero_solicitud, autorizo_nombre, estado,
                          firma_recibe_path, firma_entrega_path, entregado_en, entregado_por)
  values (v_folio, v_campus, v_nombre, p_trabajador_id,
          case when p_trabajador_id is null then btrim(p_solicitante_unidad) end,
          v_zona, nullif(btrim(p_numero_solicitud), ''), nullif(btrim(p_autorizo_nombre), ''),
          'ENTREGADA', btrim(p_firma_recibe), btrim(p_firma_entrega), now(), auth.uid())
  returning id into v_id;

  -- Materiales (HU6 E5-E10): el motivo sigue siendo obligatorio cuando se
  -- excede la periodicidad o el límite, pero solo se sugiere la autorización.
  for v_item in select * from jsonb_array_elements(coalesce(p_materiales, '[]')) loop
    select * into v_prod from productos where id = (v_item->>'producto_id')::bigint and activo;
    if v_prod.id is null then
      raise exception 'PRODUCTO_NO_REGISTRADO: Producto no registrado.';
    end if;
    v_base := convertir_a_unidad_base(v_prod.id, (v_item->>'presentacion_id')::bigint, (v_item->>'cantidad')::numeric);
    select * into v_eval from evaluar_material(v_campus, p_trabajador_id, v_zona, v_prod.id, v_base);

    if not v_eval.stock_suficiente then
      raise exception 'STOCK_INSUFICIENTE: % — solicitado %, disponible % en el campus.',
        v_prod.nombre_estandar, v_base, v_eval.disponible;
    end if;

    v_motivo := nullif(btrim(v_item->>'motivo_excepcion'), '');
    if (v_eval.excede_periodicidad or v_eval.excede_limite) then
      if v_motivo is null then
        raise exception 'MOTIVO_EXCEPCION_REQUERIDO: % excede % ; captura el motivo de la excepción (se sugiere solicitar autorización).',
          v_prod.nombre_estandar,
          concat_ws(' y ',
            case when v_eval.excede_periodicidad then 'la periodicidad (última entrega ' ||
              to_char(v_eval.ultima_entrega at time zone 'America/Hermosillo', 'DD/MM/YYYY') ||
              ', faltan ' || v_eval.dias_faltantes || ' días)' end,
            case when v_eval.excede_limite then 'el límite de la zona (límite ' || v_eval.limite_cantidad ||
              ', entregado ' || v_eval.entregado_periodo || ', solicitado ' || v_base || ')' end);
      end if;
      v_alertas := v_alertas || jsonb_build_object(
        'producto_id', v_prod.id, 'producto', v_prod.nombre_estandar,
        'excede_periodicidad', v_eval.excede_periodicidad, 'excede_limite', v_eval.excede_limite,
        'ultima_entrega', v_eval.ultima_entrega, 'dias_faltantes', v_eval.dias_faltantes,
        'limite', v_eval.limite_cantidad, 'entregado_periodo', v_eval.entregado_periodo);
    end if;

    insert into boletas_materiales (boleta_id, producto_id, presentacion_id, cantidad, cantidad_base, comentario,
                                     excede_periodicidad, excede_limite, motivo_excepcion)
    values (v_id, v_prod.id, (v_item->>'presentacion_id')::bigint, (v_item->>'cantidad')::numeric, v_base,
            nullif(btrim(v_item->>'comentario'), ''),
            v_eval.excede_periodicidad, v_eval.excede_limite,
            case when v_eval.excede_periodicidad or v_eval.excede_limite then v_motivo end);
  end loop;

  -- Herramientas (HU8 E1-E6)
  for v_item in select * from jsonb_array_elements(coalesce(p_herramientas, '[]')) loop
    select a.id, a.codigo, a.nombre, a.estado, al.campus_id into v_act
      from activos a join ubicaciones u on u.id = a.ubicacion_id join almacenes al on al.id = u.almacen_id
     where a.id = (v_item->>'activo_id')::bigint;
    if v_act.id is null or v_act.campus_id <> v_campus then
      raise exception 'ACTIVO_NO_ENCONTRADO: Activo no encontrado.';
    end if;
    if v_act.estado = 'EN_PRESTAMO' then
      select b.solicitante_nombre, p.fecha_prevista into v_custodio, v_prevista
        from prestamos p join boletas_herramientas bh on bh.id = p.boleta_herramienta_id
        join boletas b on b.id = bh.boleta_id
       where p.activo_id = v_act.id and p.estado = 'ACTIVO';
      raise exception 'ACTIVO_PRESTADO: % está prestado a % hasta el %.', v_act.codigo, v_custodio,
        to_char(v_prevista at time zone 'America/Hermosillo', 'DD/MM/YYYY');
    elsif v_act.estado <> 'DISPONIBLE' then
      raise exception 'ACTIVO_NO_DISPONIBLE: % no está disponible (%).', v_act.codigo, v_act.estado;
    end if;

    -- Un solo préstamo por tipo de herramienta: busca otra del mismo tipo en esta
    -- boleta o en un préstamo abierto del trabajador.
    select * into v_previo from herramienta_del_mismo_tipo(p_trabajador_id, v_act.nombre, v_id);
    if v_previo.boleta_id = v_id then
      raise exception 'HERRAMIENTA_MISMO_TIPO: No se pueden prestar dos herramientas "%" en la misma boleta (% y %).',
        v_act.nombre, v_previo.codigo, v_act.codigo;
    elsif v_previo.prestamo is not null then
      raise exception 'HERRAMIENTA_MISMO_TIPO: % ya tiene prestada una herramienta "%" (% en el préstamo %).',
        v_nombre, v_act.nombre, v_previo.codigo, v_previo.prestamo;
    end if;

    v_dias := (v_item->>'dias_prestamo')::int;
    if v_dias is null or v_dias <= 0 then
      raise exception 'DIAS_INVALIDOS: El tiempo de préstamo debe ser mayor a cero días.';
    end if;
    v_vencido := exists (
      select 1 from prestamos p join boletas_herramientas bh on bh.id = p.boleta_herramienta_id
        join boletas b on b.id = bh.boleta_id
       where b.trabajador_id = p_trabajador_id and p.estado = 'ACTIVO' and p.fecha_prevista < now());
    if v_vencido then
      v_alertas := v_alertas || jsonb_build_object('activo_id', v_act.id, 'solicitante_con_vencido', true);
    end if;
    insert into boletas_herramientas (boleta_id, activo_id, dias_prestamo, solicitante_con_vencido)
    values (v_id, v_act.id, v_dias, v_vencido);
  end loop;

  perform ejecutar_entrega(v_id);
  return query select v_id, v_folio, 'ENTREGADA'::text, v_alertas;
end $$;

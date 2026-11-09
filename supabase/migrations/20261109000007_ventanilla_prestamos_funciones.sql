-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 7: funciones HU6 a HU10
-- Funciones que llama el servidor (schema public, rpc):
--   validar_material      HU6 E6/E8/E10: alertas antes de agregar un material
--   validar_activo        HU8 E2-E5: estado del activo y del solicitante
--   crear_boleta          HU6 y HU8: registra la boleta; entrega o pide autorización
--   resolver_autorizacion HU6: el supervisor autoriza o rechaza
--   confirmar_entrega     HU6: entrega una boleta ya autorizada (con firmas)
--   registrar_activo      HU7
--   cambiar_estado_activo HU7/HU9: reparación terminada, baja
--   registrar_devolucion  HU9 E1-E3
--   reportar_robo_extravio         HU9 E4
--   obtener_notificaciones HU10 E4: avisos al abrir el sistema
-- Funciones internas: schema privado (no expuesto en la API).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Internas
-- ---------------------------------------------------------------------

-- Campus en el que opera el usuario (por defecto el de su perfil)
create or replace function privado.campus_de_operacion(p_campus_id bigint default null)
returns bigint
language plpgsql stable security definer set search_path = public, privado as $$
declare
  v_campus bigint := p_campus_id;
begin
  if coalesce(mi_rol(), '') not in ('ALMACENISTA', 'SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN') then
    raise exception 'SIN_PERMISO: Tu usuario no puede registrar movimientos.';
  end if;
  if v_campus is null then
    select campus_id into v_campus from usuarios where id = auth.uid();
  end if;
  if v_campus not in (select mis_campus()) then
    raise exception 'SIN_PERMISO: No tienes acceso a ese campus.';
  end if;
  return v_campus;
end $$;

create or replace function privado.crear_notificacion(
  p_usuario_id uuid, p_tipo text, p_titulo text, p_mensaje text, p_ref_tipo text, p_ref_id bigint)
returns void
language sql security definer set search_path = public, privado as $$
  insert into notificaciones (usuario_id, tipo, titulo, mensaje, referencia_tipo, referencia_id, fecha_aviso)
  values (p_usuario_id, p_tipo, p_titulo, p_mensaje, p_ref_tipo, p_ref_id,
          (now() at time zone 'America/Hermosillo')::date)
  on conflict do nothing
$$;

-- Cambia el estado de un activo y deja constancia en la bitácora
create or replace function privado.registrar_cambio_estado_activo(p_activo_id bigint, p_nuevo text, p_motivo text, p_folio text default null)
returns void
language plpgsql security definer set search_path = public, privado as $$
declare
  v_anterior text;
begin
  select estado into v_anterior from activos where id = p_activo_id for update;
  update activos set estado = p_nuevo, actualizado_en = now() where id = p_activo_id;
  insert into historial_estados_activo (activo_id, estado_anterior, estado_nuevo, motivo, folio)
  values (p_activo_id, v_anterior, p_nuevo, p_motivo, p_folio);
end $$;

-- Zona de la entrega: la indicada (si está asignada al trabajador) o la única que atiende
create or replace function privado.zona_de_entrega(p_trabajador_id bigint, p_zona_id bigint)
returns bigint
language plpgsql stable security definer set search_path = public, privado as $$
declare
  v_zona bigint := p_zona_id;
begin
  if p_trabajador_id is null then
    return p_zona_id;
  end if;
  if v_zona is null then
    select min(zona_id) into v_zona from trabajadores_zonas where trabajador_id = p_trabajador_id
    having count(*) = 1;
  elsif not exists (select 1 from trabajadores_zonas where trabajador_id = p_trabajador_id and zona_id = v_zona) then
    raise exception 'ZONA_NO_ASIGNADA: La zona no está asignada al solicitante.';
  end if;
  return v_zona;
end $$;

-- Evalúa un material para un solicitante: existencia, periodicidad y límite de zona
create or replace function privado.evaluar_material(
  p_campus_id bigint, p_trabajador_id bigint, p_zona_id bigint, p_producto_id bigint, p_cantidad_base numeric)
returns table (
  disponible numeric, ultima_entrega timestamptz, proxima_entrega timestamptz, dias_faltantes int,
  limite_cantidad numeric, limite_cada_dias int, entregado_periodo numeric,
  stock_suficiente boolean, excede_periodicidad boolean, excede_limite boolean)
language plpgsql stable security definer set search_path = public, privado as $$
declare
  v_cfg limites_material_zona%rowtype;
begin
  select coalesce(sum(e.cantidad), 0) into disponible
    from existencias e
    join ubicaciones u on u.id = e.ubicacion_id
    join almacenes a on a.id = u.almacen_id
   where e.producto_id = p_producto_id and a.campus_id = p_campus_id;
  stock_suficiente := disponible >= p_cantidad_base;
  excede_periodicidad := false;
  excede_limite := false;
  entregado_periodo := 0;

  if p_trabajador_id is not null then
    select max(b.entregado_en) into ultima_entrega
      from boletas b join boletas_materiales m on m.boleta_id = b.id
     where b.trabajador_id = p_trabajador_id and m.producto_id = p_producto_id and b.estado = 'ENTREGADA';
  end if;

  if p_zona_id is not null then
    select * into v_cfg from limites_material_zona where zona_id = p_zona_id and producto_id = p_producto_id;
  end if;

  if v_cfg.zona_id is not null then
    limite_cantidad := v_cfg.cantidad_max;
    limite_cada_dias := v_cfg.cada_dias;
    -- HU6 E8 / E9: periodicidad por trabajador
    if ultima_entrega is not null then
      proxima_entrega := ultima_entrega + v_cfg.cada_dias * interval '1 day';
      if proxima_entrega > now() then
        excede_periodicidad := true;
        dias_faltantes := ceil(extract(epoch from proxima_entrega - now()) / 86400)::int;
      end if;
    end if;
    -- HU6 E10: límite de la zona dentro del periodo
    select coalesce(sum(m.cantidad_base), 0) into entregado_periodo
      from boletas b join boletas_materiales m on m.boleta_id = b.id
     where b.zona_id = p_zona_id and m.producto_id = p_producto_id and b.estado = 'ENTREGADA'
       and b.entregado_en > now() - v_cfg.cada_dias * interval '1 day';
    excede_limite := entregado_periodo + p_cantidad_base > v_cfg.cantidad_max;
  end if;
  return next;
end $$;

-- Ejecuta una boleta: descuenta existencias y abre los préstamos
create or replace function privado.ejecutar_entrega(p_boleta_id bigint)
returns void
language plpgsql security definer set search_path = public, privado as $$
declare
  v_bol     boletas%rowtype;
  m         record;
  e         record;
  h         record;
  v_pend    numeric;
  v_toma    numeric;
  v_estado  text;
  v_folio   text;
begin
  select * into v_bol from boletas where id = p_boleta_id for update;

  -- Materiales: se toman de las ubicaciones del campus con más existencia
  for m in select bm.*, p.nombre_estandar from boletas_materiales bm
             join productos p on p.id = bm.producto_id
            where bm.boleta_id = p_boleta_id loop
    v_pend := m.cantidad_base;
    for e in select ex.ubicacion_id, ex.cantidad
               from existencias ex
               join ubicaciones u on u.id = ex.ubicacion_id
               join almacenes a on a.id = u.almacen_id
              where ex.producto_id = m.producto_id and a.campus_id = v_bol.campus_id and ex.cantidad > 0
              order by ex.cantidad desc
              for update of ex loop
      exit when v_pend <= 0;
      v_toma := least(v_pend, e.cantidad);
      perform aplicar_movimiento_inventario('SALIDA', v_bol.folio, m.producto_id, e.ubicacion_id, -v_toma,
                                     p_boleta_material_id => m.id);
      v_pend := v_pend - v_toma;
    end loop;
    if v_pend > 0 then
      raise exception 'STOCK_INSUFICIENTE: % ya no tiene existencia suficiente en el campus (faltan %).',
        m.nombre_estandar, v_pend;
    end if;
  end loop;

  -- Herramientas: se abre un préstamo por cada una
  for h in select bh.*, a.codigo from boletas_herramientas bh
             join activos a on a.id = bh.activo_id
            where bh.boleta_id = p_boleta_id loop
    select estado into v_estado from activos where id = h.activo_id for update;
    if v_estado <> 'DISPONIBLE' then
      raise exception 'ACTIVO_NO_DISPONIBLE: El activo % ya no está disponible (%).', h.codigo, v_estado;
    end if;
    v_folio := siguiente_folio('PRE');
    insert into prestamos (folio, boleta_herramienta_id, activo_id, dias_prestamo, prestado_en, fecha_prevista)
    values (v_folio, h.id, h.activo_id, h.dias_prestamo, now(), now() + h.dias_prestamo * interval '1 day');
    perform registrar_cambio_estado_activo(h.activo_id, 'EN_PRESTAMO', 'Préstamo', v_folio);
  end loop;

  update boletas set estado = 'ENTREGADA', entregado_en = now(), entregado_por = auth.uid()
   where id = p_boleta_id;
end $$;

-- ---------------------------------------------------------------------
-- HU6: validación previa de un material (para mostrar alertas en pantalla)
-- ---------------------------------------------------------------------
create or replace function public.validar_material(
  p_producto_id      bigint,
  p_cantidad         numeric,
  p_presentacion_id  bigint default null,
  p_trabajador_id      bigint default null,
  p_zona_id          bigint default null,
  p_campus_id        bigint default null)
returns table (
  disponible numeric, ultima_entrega timestamptz, proxima_entrega timestamptz, dias_faltantes int,
  limite_cantidad numeric, limite_cada_dias int, entregado_periodo numeric,
  stock_suficiente boolean, excede_periodicidad boolean, excede_limite boolean)
language plpgsql stable security definer set search_path = public, privado as $$
begin
  return query select * from evaluar_material(
    campus_de_operacion(p_campus_id), p_trabajador_id, zona_de_entrega(p_trabajador_id, p_zona_id), p_producto_id,
    convertir_a_unidad_base(p_producto_id, p_presentacion_id, p_cantidad));
end $$;

-- HU8: validación previa de un activo para préstamo
create or replace function public.validar_activo(p_codigo text, p_trabajador_id bigint default null)
returns table (activo_id bigint, codigo text, nombre text, modelo text, numero_serie text, estado text,
               custodio_actual text, fecha_prevista timestamptz, solicitante_con_vencido boolean)
language plpgsql stable security definer set search_path = public, privado as $$
declare
  v_a         record;
  v_custodio  text;
  v_prevista  timestamptz;
  v_vencido   boolean;
begin
  perform campus_de_operacion(null);
  select a.id, a.codigo, a.nombre, a.modelo, a.numero_serie, a.estado, al.campus_id into v_a
    from activos a
    join ubicaciones u on u.id = a.ubicacion_id
    join almacenes al on al.id = u.almacen_id
   where upper(btrim(a.codigo)) = upper(btrim(p_codigo));
  if v_a.id is null or v_a.campus_id not in (select mis_campus()) then
    raise exception 'ACTIVO_NO_ENCONTRADO: Activo no encontrado.';
  end if;
  select b.solicitante_nombre, p.fecha_prevista into v_custodio, v_prevista
    from prestamos p
    join boletas_herramientas bh on bh.id = p.boleta_herramienta_id
    join boletas b on b.id = bh.boleta_id
   where p.activo_id = v_a.id and p.estado = 'ACTIVO';
  v_vencido := p_trabajador_id is not null and exists (
    select 1 from prestamos p
      join boletas_herramientas bh on bh.id = p.boleta_herramienta_id
      join boletas b on b.id = bh.boleta_id
     where b.trabajador_id = p_trabajador_id and p.estado = 'ACTIVO' and p.fecha_prevista < now());
  return query select v_a.id, v_a.codigo, v_a.nombre, v_a.modelo, v_a.numero_serie, v_a.estado,
                      v_custodio, v_prevista, v_vencido;
end $$;

-- ---------------------------------------------------------------------
-- HU6 y HU8: crear boleta
--   p_materiales:   [{"producto_id":1, "cantidad":2, "presentacion_id":null,
--                     "comentario":"...", "motivo_excepcion":"..."}]
--   p_herramientas: [{"activo_id":5, "dias_prestamo":3}]
-- Si algún material excede periodicidad o límite, la boleta queda
-- PENDIENTE_AUTORIZACION y no se mueve nada; si no, se entrega en el acto.
-- ---------------------------------------------------------------------
create or replace function public.crear_boleta(
  p_materiales          jsonb  default '[]'::jsonb,
  p_herramientas        jsonb  default '[]'::jsonb,
  p_trabajador_id         bigint default null,
  p_solicitante_nombre  text   default null,
  p_solicitante_unidad  text   default null,
  p_zona_id             bigint default null,
  p_numero_solicitud    text   default null,
  p_autorizo_nombre     text   default null,
  p_supervisor_id       uuid   default null,
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
  v_requiere   boolean := false;
  v_alertas    jsonb := '[]'::jsonb;
  v_act        record;
  v_dias       int;
  v_vencido    boolean;
  v_custodio   text;
  v_prevista   timestamptz;
begin
  v_campus := campus_de_operacion(p_campus_id);

  if jsonb_array_length(coalesce(p_materiales, '[]')) + jsonb_array_length(coalesce(p_herramientas, '[]')) = 0 then
    raise exception 'BOLETA_VACIA: Agrega al menos un material o una herramienta.';
  end if;

  -- Solicitante (HU6 E2)
  if p_trabajador_id is not null then
    select * into v_trabajador from trabajadores where id = p_trabajador_id and activo;
    if v_trabajador.id is null then
      raise exception 'SOLICITANTE_NO_EXISTE: El solicitante no está en el registro de personal.';
    end if;
    v_nombre := v_trabajador.nombre;
    v_zona := zona_de_entrega(p_trabajador_id, p_zona_id);
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
                          numero_solicitud, autorizo_nombre, estado)
  values (v_folio, v_campus, v_nombre, p_trabajador_id,
          case when p_trabajador_id is null then btrim(p_solicitante_unidad) end,
          v_zona, nullif(btrim(p_numero_solicitud), ''), nullif(btrim(p_autorizo_nombre), ''),
          'PENDIENTE_AUTORIZACION')
  returning id into v_id;

  -- Materiales (HU6 E5-E10)
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
        raise exception 'MOTIVO_EXCEPCION_REQUERIDO: % excede % ; captura el motivo para solicitar autorización.',
          v_prod.nombre_estandar,
          concat_ws(' y ',
            case when v_eval.excede_periodicidad then 'la periodicidad (última entrega ' ||
              to_char(v_eval.ultima_entrega at time zone 'America/Hermosillo', 'DD/MM/YYYY') ||
              ', faltan ' || v_eval.dias_faltantes || ' días)' end,
            case when v_eval.excede_limite then 'el límite de la zona (límite ' || v_eval.limite_cantidad ||
              ', entregado ' || v_eval.entregado_periodo || ', solicitado ' || v_base || ')' end);
      end if;
      v_requiere := true;
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
    select a.id, a.codigo, a.estado, al.campus_id into v_act
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

  if v_requiere then
    if p_supervisor_id is null or not exists (
         select 1 from usuarios where id = p_supervisor_id and activo
            and rol in ('SUPERVISOR', 'SUPERVISOR_JEFE')
            and (campus_id = v_campus or exists (select 1 from usuarios_campus_adicionales pc
                                                  where pc.usuario_id = p_supervisor_id and pc.campus_id = v_campus))) then
      raise exception 'AUTORIZADOR_REQUERIDO: Selecciona el supervisor que autorizará la entrega.';
    end if;
    insert into autorizaciones (boleta_id, supervisor_id) values (v_id, p_supervisor_id);
    perform crear_notificacion(p_supervisor_id, 'AUTORIZACION_PENDIENTE', 'Autorización pendiente',
      'La boleta ' || v_folio || ' de ' || v_nombre || ' requiere tu autorización.', 'boletas', v_id);
    return query select v_id, v_folio, 'PENDIENTE_AUTORIZACION'::text, v_alertas;
    return;
  end if;

  if nullif(btrim(p_firma_recibe), '') is null or nullif(btrim(p_firma_entrega), '') is null then
    raise exception 'FIRMAS_REQUERIDAS: Deben firmar quien recibe y quien entrega.';
  end if;
  update boletas set firma_recibe_path = btrim(p_firma_recibe), firma_entrega_path = btrim(p_firma_entrega)
   where id = v_id;
  perform ejecutar_entrega(v_id);
  return query select v_id, v_folio, 'ENTREGADA'::text, v_alertas;
end $$;

-- HU6: el supervisor autoriza o rechaza
create or replace function public.resolver_autorizacion(p_boleta_id bigint, p_autorizar boolean, p_comentario text default null)
returns text
language plpgsql security definer set search_path = public, privado as $$
declare
  v_aut  autorizaciones%rowtype;
  v_bol  boletas%rowtype;
  v_rol  text := mi_rol();
begin
  select * into v_aut from autorizaciones where boleta_id = p_boleta_id for update;
  select * into v_bol from boletas where id = p_boleta_id;
  if v_aut.id is null or v_bol.campus_id not in (select mis_campus()) then
    raise exception 'AUTORIZACION_NO_EXISTE: No hay una autorización para esa boleta.';
  end if;
  if not (v_aut.supervisor_id = auth.uid() or v_rol in ('SUPERVISOR_JEFE', 'ADMIN')) then
    raise exception 'SIN_PERMISO: La autorización fue solicitada a otro supervisor.';
  end if;
  if v_aut.estado <> 'PENDIENTE' then
    raise exception 'AUTORIZACION_RESUELTA: La autorización ya fue %.', lower(v_aut.estado);
  end if;
  if p_autorizar is null then
    raise exception 'DECISION_REQUERIDA: Indica si autorizas o rechazas.';
  end if;

  update autorizaciones
     set estado = case when p_autorizar then 'AUTORIZADA' else 'RECHAZADA' end,
         comentario = nullif(btrim(p_comentario), ''), resuelto_en = now(), resuelto_por = auth.uid()
   where id = v_aut.id;
  update boletas set estado = case when p_autorizar then 'AUTORIZADA' else 'RECHAZADA' end
   where id = p_boleta_id;
  perform crear_notificacion(v_bol.creado_por, 'AUTORIZACION_RESUELTA',
    case when p_autorizar then 'Entrega autorizada' else 'Entrega rechazada' end,
    'La boleta ' || v_bol.folio || ' fue ' || case when p_autorizar then 'autorizada' else 'rechazada' end || '.',
    'boletas', p_boleta_id);
  return case when p_autorizar then 'AUTORIZADA' else 'RECHAZADA' end;
end $$;

-- HU6: entregar una boleta autorizada
create or replace function public.confirmar_entrega(p_boleta_id bigint, p_firma_recibe text, p_firma_entrega text)
returns text
language plpgsql security definer set search_path = public, privado as $$
declare
  v_bol boletas%rowtype;
begin
  select * into v_bol from boletas where id = p_boleta_id for update;
  if v_bol.id is null then
    raise exception 'BOLETA_NO_EXISTE: La boleta no existe.';
  end if;
  perform campus_de_operacion(v_bol.campus_id);
  if v_bol.estado <> 'AUTORIZADA' then
    raise exception 'BOLETA_NO_AUTORIZADA: La boleta está %.', lower(v_bol.estado);
  end if;
  if nullif(btrim(p_firma_recibe), '') is null or nullif(btrim(p_firma_entrega), '') is null then
    raise exception 'FIRMAS_REQUERIDAS: Deben firmar quien recibe y quien entrega.';
  end if;
  update boletas set firma_recibe_path = btrim(p_firma_recibe), firma_entrega_path = btrim(p_firma_entrega)
   where id = p_boleta_id;
  perform ejecutar_entrega(p_boleta_id);
  return v_bol.folio;
end $$;

-- ---------------------------------------------------------------------
-- HU7: registro de activo
-- ---------------------------------------------------------------------
create or replace function public.registrar_activo(
  p_codigo        text,
  p_nombre        text,
  p_modelo        text,
  p_numero_serie  text,
  p_almacen_id    bigint,
  p_ubicacion     text    default null,
  p_marca         text    default null,
  p_valor         numeric default null)
returns table (activo_id bigint, codigo text, estado text)
language plpgsql security definer set search_path = public, privado as $$
declare
  v_faltan  text;
  v_existe  record;
  v_id      bigint;
begin
  perform validar_almacen(p_almacen_id);
  v_faltan := concat_ws(', ',
    case when nullif(btrim(p_codigo), '') is null then 'código' end,
    case when nullif(btrim(p_nombre), '') is null then 'nombre' end,
    case when nullif(btrim(p_modelo), '') is null then 'modelo' end,
    case when nullif(btrim(p_numero_serie), '') is null then 'número de serie' end);
  if v_faltan <> '' then
    raise exception 'CAMPOS_REQUERIDOS: Falta %.', v_faltan;
  end if;
  select a.codigo, a.nombre, a.modelo into v_existe from activos a
   where upper(btrim(a.codigo)) = upper(btrim(p_codigo));
  if found then
    raise exception 'ACTIVO_DUPLICADO: Ya existe el activo % (% %).', v_existe.codigo, v_existe.nombre, v_existe.modelo;
  end if;
  insert into activos (codigo, nombre, marca, modelo, numero_serie, valor, ubicacion_id)
  values (btrim(p_codigo), btrim(p_nombre), nullif(btrim(p_marca), ''), btrim(p_modelo), btrim(p_numero_serie),
          p_valor, obtener_o_crear_ubicacion(p_almacen_id, p_ubicacion))
  returning id into v_id;
  insert into historial_estados_activo (activo_id, estado_anterior, estado_nuevo, motivo)
  values (v_id, null, 'DISPONIBLE', 'Alta del activo');
  return query select v_id, btrim(p_codigo), 'DISPONIBLE'::text;
end $$;

-- HU7/HU9: cambios manuales de estado (reparación terminada, a reparación, baja)
create or replace function public.cambiar_estado_activo(p_activo_id bigint, p_estado text, p_motivo text)
returns text
language plpgsql security definer set search_path = public, privado as $$
declare
  v_act record;
begin
  select a.estado, al.campus_id into v_act
    from activos a join ubicaciones u on u.id = a.ubicacion_id join almacenes al on al.id = u.almacen_id
   where a.id = p_activo_id;
  if v_act.campus_id is null then
    raise exception 'ACTIVO_NO_ENCONTRADO: Activo no encontrado.';
  end if;
  perform campus_de_operacion(v_act.campus_id);
  if p_estado not in ('DISPONIBLE', 'EN_REPARACION', 'DE_BAJA') then
    raise exception 'ESTADO_INVALIDO: Solo puedes cambiar a Disponible, En reparación o De baja.';
  end if;
  if v_act.estado = 'EN_PRESTAMO' then
    raise exception 'ACTIVO_PRESTADO: Registra primero la devolución.';
  end if;
  if v_act.estado = p_estado then
    raise exception 'SIN_CAMBIO: El activo ya está en ese estado.';
  end if;
  if nullif(btrim(p_motivo), '') is null then
    raise exception 'MOTIVO_REQUERIDO: Captura el motivo del cambio.';
  end if;
  perform registrar_cambio_estado_activo(p_activo_id, p_estado, btrim(p_motivo));
  return p_estado;
end $$;

-- ---------------------------------------------------------------------
-- HU9: devolución con dictamen físico
-- ---------------------------------------------------------------------
create or replace function public.registrar_devolucion(
  p_prestamo_id       bigint,
  p_condicion         text,      -- 'BUEN_ESTADO' | 'DANADO'
  p_firma_entrega     text,      -- firma del trabajador que regresa el equipo
  p_firma_recibe      text,      -- firma del almacenista
  p_descripcion_dano  text default null,
  p_observaciones     text default null)
returns table (devolucion_id bigint, folio text, dias_retraso int, estado_activo text)
language plpgsql security definer set search_path = public, privado as $$
declare
  v_pre     prestamos%rowtype;
  v_campus  bigint;
  v_folio   text;
  v_retraso int;
  v_estado  text;
  v_id      bigint;
begin
  select * into v_pre from prestamos where id = p_prestamo_id for update;
  if v_pre.id is null then
    raise exception 'PRESTAMO_NO_EXISTE: El préstamo no existe.';
  end if;
  select al.campus_id into v_campus from activos a
    join ubicaciones u on u.id = a.ubicacion_id join almacenes al on al.id = u.almacen_id
   where a.id = v_pre.activo_id;
  perform campus_de_operacion(v_campus);
  if v_pre.estado <> 'ACTIVO' then
    raise exception 'PRESTAMO_CERRADO: El préstamo ya está cerrado (%).', lower(v_pre.estado);
  end if;
  if p_condicion not in ('BUEN_ESTADO', 'DANADO') then
    raise exception 'CONDICION_INVALIDA: Indica si el equipo regresó en buen estado o dañado.';
  end if;
  if p_condicion = 'DANADO' and nullif(btrim(p_descripcion_dano), '') is null then
    raise exception 'DESCRIPCION_REQUERIDA: Describe el daño o la falla.';
  end if;
  if nullif(btrim(p_firma_entrega), '') is null or nullif(btrim(p_firma_recibe), '') is null then
    raise exception 'FIRMAS_REQUERIDAS: Deben firmar el trabajador y el almacenista.';
  end if;

  -- HU9 E3: días naturales de retraso, en hora de Sonora
  v_retraso := greatest(0, (now() at time zone 'America/Hermosillo')::date
                         - (v_pre.fecha_prevista at time zone 'America/Hermosillo')::date);
  v_folio := siguiente_folio('DEV');
  insert into devoluciones (folio, prestamo_id, condicion, descripcion_dano, dias_retraso,
                              firma_entrega_path, firma_recibe_path, observaciones)
  values (v_folio, v_pre.id, p_condicion, nullif(btrim(p_descripcion_dano), ''), v_retraso,
          btrim(p_firma_entrega), btrim(p_firma_recibe), nullif(btrim(p_observaciones), ''))
  returning id into v_id;
  update prestamos set estado = 'DEVUELTO' where id = v_pre.id;

  v_estado := case when p_condicion = 'DANADO' then 'EN_REPARACION' else 'DISPONIBLE' end;
  perform registrar_cambio_estado_activo(v_pre.activo_id, v_estado,
    case when p_condicion = 'DANADO' then 'Devuelto dañado: ' || btrim(p_descripcion_dano) else 'Devolución' end,
    v_folio);
  return query select v_id, v_folio, v_retraso, v_estado;
end $$;

-- HU9 E4: robo o extravío
create or replace function public.reportar_robo_extravio(p_prestamo_id bigint, p_declaracion text)
returns text
language plpgsql security definer set search_path = public, privado as $$
declare
  v_pre     prestamos%rowtype;
  v_campus  bigint;
  v_folio   text;
begin
  select * into v_pre from prestamos where id = p_prestamo_id for update;
  if v_pre.id is null then
    raise exception 'PRESTAMO_NO_EXISTE: El préstamo no existe.';
  end if;
  select al.campus_id into v_campus from activos a
    join ubicaciones u on u.id = a.ubicacion_id join almacenes al on al.id = u.almacen_id
   where a.id = v_pre.activo_id;
  perform campus_de_operacion(v_campus);
  if v_pre.estado <> 'ACTIVO' then
    raise exception 'PRESTAMO_CERRADO: El préstamo ya está cerrado (%).', lower(v_pre.estado);
  end if;
  if nullif(btrim(p_declaracion), '') is null then
    raise exception 'DECLARACION_REQUERIDA: Captura la declaración del trabajador.';
  end if;
  v_folio := siguiente_folio('ROB');
  insert into reportes_robo_extravio (folio, prestamo_id, declaracion) values (v_folio, v_pre.id, btrim(p_declaracion));
  update prestamos set estado = 'ROBO_EXTRAVIO' where id = v_pre.id;
  perform registrar_cambio_estado_activo(v_pre.activo_id, 'ROBO_EXTRAVIO', 'Reporte de robo o extravío', v_folio);
  return v_folio;
end $$;

-- ---------------------------------------------------------------------
-- HU10: seguimiento de préstamos (estados calculados al consultar)
-- ---------------------------------------------------------------------
create or replace view public.vista_seguimiento_prestamos
with (security_invoker = true) as
select p.id as prestamo_id, p.folio, b.folio as boleta_folio,
       a.id as activo_id, a.codigo, a.nombre as herramienta, a.modelo, a.numero_serie,
       b.trabajador_id, b.solicitante_nombre as custodio, b.numero_solicitud,
       al.campus_id, p.dias_prestamo, p.prestado_en, p.fecha_prevista, p.estado,
       case
         when p.estado <> 'ACTIVO' then p.estado
         when now() > p.fecha_prevista then 'VENCIDO'
         when p.fecha_prevista - now() <= interval '1 day' then 'PROXIMO_A_VENCER'
         else 'VIGENTE'
       end as seguimiento,
       case when p.estado = 'ACTIVO' and now() <= p.fecha_prevista
            then (p.fecha_prevista at time zone 'America/Hermosillo')::date
                 - (now() at time zone 'America/Hermosillo')::date end as dias_restantes,
       case when p.estado = 'ACTIVO' and now() > p.fecha_prevista
            then greatest(0, (now() at time zone 'America/Hermosillo')::date
                 - (p.fecha_prevista at time zone 'America/Hermosillo')::date)
            else d.dias_retraso end as dias_retraso,
       d.devuelto_en, d.condicion
  from prestamos p
  join boletas_herramientas bh on bh.id = p.boleta_herramienta_id
  join boletas b on b.id = bh.boleta_id
  join activos a on a.id = p.activo_id
  join ubicaciones u on u.id = a.ubicacion_id
  join almacenes al on al.id = u.almacen_id
  left join devoluciones d on d.prestamo_id = p.id;

-- HU10 E4: al abrir la app se generan (una vez al día) los avisos de
-- préstamos vencidos de tus campus y se devuelven tus avisos sin leer
create or replace function public.obtener_notificaciones()
returns setof public.notificaciones
language plpgsql security definer set search_path = public, privado as $$
declare
  r record;
begin
  if coalesce(mi_rol(), '') in ('ALMACENISTA', 'SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN') then
    for r in select v.prestamo_id, v.codigo, v.herramienta, v.custodio, v.dias_retraso
               from vista_seguimiento_prestamos v
              where v.seguimiento = 'VENCIDO' and v.campus_id in (select mis_campus()) loop
      perform crear_notificacion(auth.uid(), 'PRESTAMO_VENCIDO', 'Préstamo vencido',
        r.herramienta || ' ' || r.codigo || ' con ' || r.custodio || ' · ' || r.dias_retraso || ' día(s) de retraso',
        'prestamos', r.prestamo_id);
    end loop;
  end if;
  return query select * from notificaciones where usuario_id = auth.uid() and leida_en is null
                order by creado_en desc;
end $$;

-- ---------------------------------------------------------------------
-- HU4 ajustada: solo se reingresa material de boletas ya entregadas
-- ---------------------------------------------------------------------
create or replace function public.registrar_reingreso(
  p_boleta_material_id bigint,
  p_almacen_id         bigint,
  p_cantidad           numeric,
  p_ubicacion          text   default null,
  p_presentacion_id    bigint default null,
  p_observaciones      text   default null)
returns table (entrada_id bigint, folio text, existencia_ubicacion numeric)
language plpgsql security definer set search_path = public, privado as $$
declare
  v_campus       bigint;
  v_linea        boletas_materiales%rowtype;
  v_bol          boletas%rowtype;
  v_base         numeric;
  v_reingresado  numeric;
  v_ubicacion    bigint;
  v_folio        text;
  v_id           bigint;
  v_saldo        numeric;
begin
  v_campus := validar_almacen(p_almacen_id);
  select * into v_linea from boletas_materiales where id = p_boleta_material_id for update;
  if v_linea.id is null then
    raise exception 'BOLETA_NO_EXISTE: El material de la boleta no existe.';
  end if;
  select * into v_bol from boletas where id = v_linea.boleta_id;
  if v_bol.campus_id <> v_campus then
    raise exception 'CAMPUS_DISTINTO: La boleta es de otro campus.';
  end if;
  if v_bol.estado <> 'ENTREGADA' then
    raise exception 'BOLETA_NO_ENTREGADA: La boleta % no se ha entregado.', v_bol.folio;
  end if;
  v_base := convertir_a_unidad_base(v_linea.producto_id, p_presentacion_id, p_cantidad);
  select coalesce(sum(cantidad_base), 0) into v_reingresado
    from entradas where boleta_material_id = p_boleta_material_id;
  if v_reingresado + v_base > v_linea.cantidad_base then
    raise exception 'REINGRESO_EXCEDE: Se entregaron % y ya se reingresaron %; verifica la cantidad real.',
      v_linea.cantidad_base, v_reingresado;
  end if;
  v_ubicacion := obtener_o_crear_ubicacion(p_almacen_id, p_ubicacion);
  v_folio := siguiente_folio('REI');
  insert into entradas (folio, motivo, producto_id, ubicacion_id, presentacion_id, cantidad, cantidad_base,
                           tipo_origen, boleta_material_id, observaciones)
  values (v_folio, 'REINGRESO_TRASPASO', v_linea.producto_id, v_ubicacion, p_presentacion_id, p_cantidad, v_base,
          'BOLETA', p_boleta_material_id, nullif(btrim(p_observaciones), ''))
  returning id into v_id;
  v_saldo := aplicar_movimiento_inventario('REINGRESO', v_folio, v_linea.producto_id, v_ubicacion, v_base, p_entrada_id => v_id);
  return query select v_id, v_folio, v_saldo;
end $$;

-- ---------------------------------------------------------------------
-- Permisos de ejecución
-- ---------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon;
revoke execute on function
  privado.zona_de_entrega(bigint, bigint),
  privado.campus_de_operacion(bigint),
  privado.crear_notificacion(uuid, text, text, text, text, bigint),
  privado.registrar_cambio_estado_activo(bigint, text, text, text),
  privado.evaluar_material(bigint, bigint, bigint, bigint, numeric),
  privado.ejecutar_entrega(bigint)
from public, anon, authenticated;
grant execute on function
  public.validar_material(bigint, numeric, bigint, bigint, bigint, bigint),
  public.validar_activo(text, bigint),
  public.crear_boleta(jsonb, jsonb, bigint, text, text, bigint, text, text, uuid, text, text, bigint),
  public.resolver_autorizacion(bigint, boolean, text),
  public.confirmar_entrega(bigint, text, text),
  public.registrar_activo(text, text, text, text, bigint, text, text, numeric),
  public.cambiar_estado_activo(bigint, text, text),
  public.registrar_devolucion(bigint, text, text, text, text, text),
  public.reportar_robo_extravio(bigint, text),
  public.obtener_notificaciones(),
  public.registrar_reingreso(bigint, bigint, numeric, text, bigint, text)
to authenticated;

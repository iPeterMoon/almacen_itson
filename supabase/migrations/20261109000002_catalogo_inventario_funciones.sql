-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 2: funciones y vistas
-- Toda operación que mueve existencias o emite folios es una función que
-- el servidor llama con rpc() usando el token del usuario, y corre
-- completa o no corre (una sola transacción).
--
-- Los errores de negocio se lanzan como  CODIGO: mensaje ; el servidor
-- los traduce a HTTP y la app muestra el mensaje.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Folios: PREFIJO-AAAA-NNNN, consecutivo por tipo y año, sin huecos.
-- Para cambiar el formato (por campus, otros prefijos) solo se toca aquí.
-- ---------------------------------------------------------------------
create or replace function public.siguiente_folio(p_tipo text)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_anio int := extract(year from (now() at time zone 'America/Hermosillo'))::int;
  v_num  int;
begin
  insert into folios_consecutivos as f (tipo, anio, ultimo)
  values (p_tipo, v_anio, 1)
  on conflict (tipo, anio) do update set ultimo = f.ultimo + 1
  returning f.ultimo into v_num;
  -- El renglón queda bloqueado hasta que termina la transacción: si la
  -- operación falla, el número se libera y no quedan huecos.
  return p_tipo || '-' || v_anio || '-' || lpad(v_num::text, greatest(4, length(v_num::text)), '0');
end $$;

-- ---------------------------------------------------------------------
-- Contexto del usuario que llama (para políticas RLS y validaciones)
-- ---------------------------------------------------------------------
create or replace function public.mi_rol()
returns text
language sql stable security definer set search_path = public as $$
  select rol from usuarios where id = auth.uid() and activo
$$;

create or replace function public.mis_campus()
returns setof bigint
language sql stable security definer set search_path = public as $$
  select campus_id from usuarios where id = auth.uid() and activo
  union
  select pc.campus_id
    from usuarios_campus_adicionales pc
    join usuarios p on p.id = pc.usuario_id
   where pc.usuario_id = auth.uid() and p.activo and p.rol = 'SUPERVISOR_JEFE'
$$;

-- Lanza error si el usuario no puede operar en el almacén indicado
create or replace function public.validar_almacen(p_almacen_id bigint)
returns bigint  -- devuelve el campus del almacén
language plpgsql stable security definer set search_path = public as $$
declare
  v_campus bigint;
begin
  if p_almacen_id is null then
    raise exception 'ALMACEN_REQUERIDO: Selecciona el almacén.';
  end if;
  select campus_id into v_campus from almacenes where id = p_almacen_id and activo;
  if v_campus is null then
    raise exception 'ALMACEN_NO_EXISTE: El almacén no existe o está inactivo.';
  end if;
  if coalesce(mi_rol(), '') not in ('ALMACENISTA', 'SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN') then
    raise exception 'SIN_PERMISO: Tu usuario no puede registrar movimientos.';
  end if;
  if v_campus not in (select mis_campus()) then
    raise exception 'SIN_PERMISO: El almacén no pertenece a tu campus.';
  end if;
  return v_campus;
end $$;

-- Busca la ubicación dentro del almacén o la crea si es nueva
create or replace function public.obtener_o_crear_ubicacion(p_almacen_id bigint, p_descripcion text)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_desc text := nullif(btrim(p_descripcion), '');
  v_id   bigint;
begin
  select id into v_id from ubicaciones
   where almacen_id = p_almacen_id
     and lower(coalesce(btrim(descripcion), '')) = lower(coalesce(v_desc, ''));
  if v_id is null then
    insert into ubicaciones (almacen_id, descripcion) values (p_almacen_id, v_desc)
    on conflict do nothing
    returning id into v_id;
    if v_id is null then  -- otro usuario la creó al mismo tiempo
      select id into v_id from ubicaciones
       where almacen_id = p_almacen_id
         and lower(coalesce(btrim(descripcion), '')) = lower(coalesce(v_desc, ''));
    end if;
  end if;
  return v_id;
end $$;

-- Convierte una cantidad capturada en una presentación a unidad base
create or replace function public.convertir_a_unidad_base(p_producto_id bigint, p_presentacion_id bigint, p_cantidad numeric)
returns numeric
language plpgsql stable security definer set search_path = public as $$
declare
  v_factor numeric;
begin
  if p_cantidad is null or p_cantidad <= 0 then
    raise exception 'CANTIDAD_INVALIDA: La cantidad debe ser mayor a cero.';
  end if;
  if p_presentacion_id is null then
    return p_cantidad;
  end if;
  select factor_a_base into v_factor from presentaciones_producto
   where id = p_presentacion_id and producto_id = p_producto_id and activo;
  if v_factor is null then
    raise exception 'PRESENTACION_INVALIDA: La presentación no corresponde al producto.';
  end if;
  return round(p_cantidad * v_factor, 3);
end $$;

-- Núcleo del kardex: aplica un cambio de existencia y lo registra.
-- Bloquea el saldo (FOR UPDATE) para que dos operaciones simultáneas
-- no lean la misma existencia.
create or replace function public.aplicar_movimiento_inventario(
  p_tipo text, p_folio text, p_producto_id bigint, p_ubicacion_id bigint, p_cantidad numeric,
  p_entrada_id bigint default null, p_ajuste_id bigint default null, p_boleta_material_id bigint default null)
returns numeric  -- existencia resultante
language plpgsql security definer set search_path = public as $$
declare
  v_actual numeric;
begin
  insert into existencias (producto_id, ubicacion_id, cantidad)
  values (p_producto_id, p_ubicacion_id, 0)
  on conflict do nothing;

  select cantidad into v_actual from existencias
   where producto_id = p_producto_id and ubicacion_id = p_ubicacion_id
   for update;

  if v_actual + p_cantidad < 0 then
    raise exception 'STOCK_INSUFICIENTE: Existencia disponible: %.', v_actual;
  end if;

  update existencias
     set cantidad = v_actual + p_cantidad, actualizado_en = now()
   where producto_id = p_producto_id and ubicacion_id = p_ubicacion_id;

  insert into movimientos_inventario (tipo, folio, producto_id, ubicacion_id, cantidad, existencia_resultante,
                              entrada_id, ajuste_id, boleta_material_id)
  values (p_tipo, p_folio, p_producto_id, p_ubicacion_id, p_cantidad, v_actual + p_cantidad,
          p_entrada_id, p_ajuste_id, p_boleta_material_id);

  return v_actual + p_cantidad;
end $$;

-- ---------------------------------------------------------------------
-- RPC HU2: registrar entrada por compra o por traspaso
-- ---------------------------------------------------------------------
create or replace function public.registrar_entrada(
  p_producto_id       bigint,
  p_almacen_id        bigint,
  p_cantidad          numeric,
  p_motivo            text,                     -- 'COMPRA' | 'REINGRESO_TRASPASO'
  p_ubicacion         text    default null,     -- descripción opcional (HU2 E5)
  p_presentacion_id   bigint  default null,
  p_numero_factura    text    default null,
  p_numero_partida    text    default null,
  p_proveedor_id      bigint  default null,     -- proveedor ya registrado...
  p_proveedor_nuevo   text    default null,     -- ...o nombre de uno nuevo
  p_tipo_origen       text    default null,     -- 'CAMPUS' | 'UNIDAD'
  p_origen_campus_id  bigint  default null,
  p_origen_unidad_id  bigint  default null,
  p_origen_detalle    text    default null,
  p_observaciones     text    default null)
returns table (entrada_id bigint, folio text, existencia_ubicacion numeric)
language plpgsql security definer set search_path = public as $$
declare
  v_ubicacion bigint;
  v_base      numeric;
  v_proveedor bigint := p_proveedor_id;
  v_folio     text;
  v_id        bigint;
  v_saldo     numeric;
begin
  perform validar_almacen(p_almacen_id);

  if not exists (select 1 from productos where id = p_producto_id and activo) then
    raise exception 'PRODUCTO_NO_REGISTRADO: Producto no registrado. Dalo de alta en el catálogo.';
  end if;

  v_base := convertir_a_unidad_base(p_producto_id, p_presentacion_id, p_cantidad);

  if p_motivo = 'COMPRA' then
    if v_proveedor is null and nullif(btrim(p_proveedor_nuevo), '') is not null then
      insert into proveedores (nombre) values (btrim(p_proveedor_nuevo))
      on conflict ((lower(btrim(nombre)))) do update set activo = true
      returning id into v_proveedor;
    end if;
    if nullif(btrim(p_numero_factura), '') is null or nullif(btrim(p_numero_partida), '') is null
       or v_proveedor is null then
      raise exception 'DATOS_COMPRA_FALTANTES: La compra requiere número de factura, número de partida y proveedor.';
    end if;
    if p_tipo_origen is not null then
      raise exception 'ORIGEN_NO_APLICA: Una compra no lleva origen.';
    end if;
  elsif p_motivo = 'REINGRESO_TRASPASO' then
    if p_tipo_origen not in ('CAMPUS', 'UNIDAD') then
      raise exception 'ORIGEN_REQUERIDO: Indica si el material viene de otro campus o de otra unidad. Para sobrantes de una boleta usa registrar_reingreso.';
    end if;
  else
    raise exception 'MOTIVO_INVALIDO: Motivo de entrada no válido.';
  end if;

  v_ubicacion := obtener_o_crear_ubicacion(p_almacen_id, p_ubicacion);
  v_folio := siguiente_folio('ENT');

  insert into entradas (folio, motivo, producto_id, ubicacion_id, presentacion_id, cantidad, cantidad_base,
                           numero_factura, numero_partida, proveedor_id,
                           tipo_origen, origen_campus_id, origen_unidad_id, origen_detalle, observaciones)
  values (v_folio, p_motivo, p_producto_id, v_ubicacion, p_presentacion_id, p_cantidad, v_base,
          case when p_motivo = 'COMPRA' then btrim(p_numero_factura) end,
          case when p_motivo = 'COMPRA' then btrim(p_numero_partida) end,
          case when p_motivo = 'COMPRA' then v_proveedor end,
          p_tipo_origen,
          case when p_tipo_origen = 'CAMPUS' then p_origen_campus_id end,
          case when p_tipo_origen = 'UNIDAD' then p_origen_unidad_id end,
          nullif(btrim(p_origen_detalle), ''), nullif(btrim(p_observaciones), ''))
  returning id into v_id;

  v_saldo := aplicar_movimiento_inventario('ENTRADA', v_folio, p_producto_id, v_ubicacion, v_base, p_entrada_id => v_id);

  return query select v_id, v_folio, v_saldo;
end $$;

-- ---------------------------------------------------------------------
-- RPC HU4: reingreso de sobrantes ligado a la boleta de origen
-- ---------------------------------------------------------------------
create or replace function public.registrar_reingreso(
  p_boleta_material_id bigint,
  p_almacen_id         bigint,
  p_cantidad           numeric,
  p_ubicacion          text   default null,
  p_presentacion_id    bigint default null,
  p_observaciones      text   default null)
returns table (entrada_id bigint, folio text, existencia_ubicacion numeric)
language plpgsql security definer set search_path = public as $$
declare
  v_campus       bigint;
  v_linea        boletas_materiales%rowtype;
  v_campus_bol   bigint;
  v_base         numeric;
  v_reingresado  numeric;
  v_ubicacion    bigint;
  v_folio        text;
  v_id           bigint;
  v_saldo        numeric;
begin
  v_campus := validar_almacen(p_almacen_id);

  -- Bloquea el renglón de la boleta para que dos reingresos simultáneos no rebasen lo entregado
  select * into v_linea from boletas_materiales where id = p_boleta_material_id for update;
  if v_linea.id is null then
    raise exception 'BOLETA_NO_EXISTE: El material de la boleta no existe.';
  end if;
  select campus_id into v_campus_bol from boletas where id = v_linea.boleta_id;
  if v_campus_bol <> v_campus then
    raise exception 'CAMPUS_DISTINTO: La boleta es de otro campus.';
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
-- RPC HU5: ajuste por conteo físico
-- ---------------------------------------------------------------------
create or replace function public.registrar_ajuste(
  p_producto_id     bigint,
  p_almacen_id      bigint,
  p_cantidad_nueva  numeric,
  p_motivo          text,
  p_ubicacion       text default null)
returns table (ajuste_id bigint, folio text, diferencia numeric)
language plpgsql security definer set search_path = public as $$
declare
  v_ubicacion bigint;
  v_actual    numeric;
  v_folio     text;
  v_id        bigint;
begin
  perform validar_almacen(p_almacen_id);

  if nullif(btrim(p_motivo), '') is null then
    raise exception 'MOTIVO_REQUERIDO: Captura el motivo del ajuste.';
  end if;
  if p_cantidad_nueva is null or p_cantidad_nueva < 0 then
    raise exception 'CANTIDAD_INVALIDA: La cantidad contada no puede ser negativa.';
  end if;
  if not exists (select 1 from productos where id = p_producto_id) then
    raise exception 'PRODUCTO_NO_REGISTRADO: Producto no registrado.';
  end if;

  v_ubicacion := obtener_o_crear_ubicacion(p_almacen_id, p_ubicacion);

  insert into existencias (producto_id, ubicacion_id, cantidad)
  values (p_producto_id, v_ubicacion, 0) on conflict do nothing;
  select cantidad into v_actual from existencias
   where producto_id = p_producto_id and ubicacion_id = v_ubicacion for update;

  if v_actual = p_cantidad_nueva then
    raise exception 'SIN_DIFERENCIA: La cantidad contada es igual a la existencia; no hay nada que ajustar.';
  end if;

  v_folio := siguiente_folio('AJU');
  insert into ajustes_inventario (folio, producto_id, ubicacion_id, cantidad_anterior, cantidad_nueva, motivo)
  values (v_folio, p_producto_id, v_ubicacion, v_actual, p_cantidad_nueva, btrim(p_motivo))
  returning id into v_id;

  perform aplicar_movimiento_inventario('AJUSTE', v_folio, p_producto_id, v_ubicacion,
                                 p_cantidad_nueva - v_actual, p_ajuste_id => v_id);

  return query select v_id, v_folio, p_cantidad_nueva - v_actual;
end $$;

-- ---------------------------------------------------------------------
-- Vistas para HU3 (security_invoker: respetan las políticas RLS)
-- ---------------------------------------------------------------------

-- Existencia por ubicación: alimenta el detalle "cantidad de cada ubicación"
create or replace view public.vista_existencias_por_ubicacion
with (security_invoker = true) as
select e.producto_id,
       a.campus_id,
       a.id   as almacen_id,
       a.nombre as almacen,
       u.id   as ubicacion_id,
       u.descripcion as ubicacion,
       e.cantidad,
       e.actualizado_en
  from existencias e
  join ubicaciones u on u.id = e.ubicacion_id
  join almacenes   a on a.id = u.almacen_id;

-- Historial general de movimientos (HU5 E1, base para Reportes)
create or replace view public.vista_historial_movimientos
with (security_invoker = true) as
select m.id, m.creado_en, m.tipo, m.folio,
       p.codigo, p.nombre_estandar, p.alias,
       a.campus_id, a.nombre as almacen, u.descripcion as ubicacion,
       m.cantidad, m.existencia_resultante,
       um.clave as unidad,
       usr.nombre as registrado_por,
       aj.motivo as motivo_ajuste,
       en.motivo as motivo_entrada
  from movimientos_inventario m
  join productos      p   on p.id  = m.producto_id
  join unidades_medida um  on um.id = p.unidad_base_id
  join ubicaciones     u   on u.id  = m.ubicacion_id
  join almacenes       a   on a.id  = u.almacen_id
  left join usuarios   usr on usr.id = m.creado_por
  left join ajustes_inventario   aj  on aj.id = m.ajuste_id
  left join entradas  en  on en.id = m.entrada_id;

-- RPC HU3: búsqueda y filtros del catálogo con existencia del campus
create or replace function public.buscar_productos(
  p_texto         text   default null,
  p_categoria_id  bigint default null,
  p_unidad_id     bigint default null,
  p_tipo          text   default null,   -- 'SERVICIOS_GENERALES' | 'MANTENIMIENTO'
  p_almacen_id    bigint default null,
  p_limite        int    default 50,
  p_desplazar     int    default 0)
returns table (
  producto_id bigint, codigo text, nombre_estandar text, alias text,
  categoria text, unidad text, tipo text, mas_comunes boolean,
  existencia numeric, ultima_entrada timestamptz, ultima_salida timestamptz)
language sql stable security invoker set search_path = public as $$
  select p.id, p.codigo, p.nombre_estandar, p.alias,
         c.nombre, um.clave, p.tipo, p.mas_comunes,
         coalesce((select sum(v.cantidad) from vista_existencias_por_ubicacion v
                    where v.producto_id = p.id
                      and (p_almacen_id is null or v.almacen_id = p_almacen_id)), 0),
         (select max(m.creado_en) from movimientos_inventario m
           where m.producto_id = p.id and m.tipo in ('ENTRADA', 'REINGRESO')),
         (select max(m.creado_en) from movimientos_inventario m
           where m.producto_id = p.id and m.tipo = 'SALIDA')
    from productos p
    join categorias     c  on c.id  = p.categoria_id
    join unidades_medida um on um.id = p.unidad_base_id
   where p.activo
     and (nullif(btrim(p_texto), '') is null
          or p.codigo ilike '%' || btrim(p_texto) || '%'
          or p.nombre_estandar ilike '%' || btrim(p_texto) || '%'
          or p.alias ilike '%' || btrim(p_texto) || '%')
     and (p_categoria_id is null or p.categoria_id = p_categoria_id)
     and (p_unidad_id is null or p.unidad_base_id = p_unidad_id)
     and (p_tipo is null or p.tipo = p_tipo or p.tipo = 'AMBOS')
     and (p_almacen_id is null or exists (
          select 1 from vista_existencias_por_ubicacion v
           where v.producto_id = p.id and v.almacen_id = p_almacen_id))
   order by p.mas_comunes desc, p.nombre_estandar
   limit p_limite offset p_desplazar
$$;

-- ---------------------------------------------------------------------
-- Permisos de ejecución: solo usuarios autenticados llaman las RPC;
-- las funciones internas no se exponen.
-- ---------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon;
revoke execute on function
  public.siguiente_folio(text),
  public.obtener_o_crear_ubicacion(bigint, text),
  public.aplicar_movimiento_inventario(text, text, bigint, bigint, numeric, bigint, bigint, bigint),
  public.validar_almacen(bigint)
from authenticated;
grant execute on function
  public.registrar_entrada(bigint, bigint, numeric, text, text, bigint, text, text, bigint, text, text, bigint, bigint, text, text),
  public.registrar_reingreso(bigint, bigint, numeric, text, bigint, text),
  public.registrar_ajuste(bigint, bigint, numeric, text, text),
  public.buscar_productos(text, bigint, bigint, text, bigint, int, int),
  public.convertir_a_unidad_base(bigint, bigint, numeric),
  public.mi_rol(),
  public.mis_campus()
to authenticated;

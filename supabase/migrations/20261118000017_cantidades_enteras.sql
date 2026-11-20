-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 17: cantidades enteras en boletas
-- La cantidad capturada en una boleta o entrada es el número de
-- presentaciones completas (botellas, cajas, piezas), por lo que debe ser
-- entera. La cantidad base sí puede ser decimal: una botella de 355 ml
-- equivale a 0.355 L. El stock y los movimientos se guardan en unidad base
-- y conservan sus decimales.
-- =====================================================================

-- Antes de agregar los CHECK, revisa que no haya cantidades capturadas con
-- decimales. Si hay filas así, la migración se detiene con el detalle para
-- corregirlas de forma consciente.
do $$
declare
  v_tabla   text;
  v_columna text;
  v_total   bigint;
begin
  for v_tabla, v_columna in
    select *
      from (values
        ('boletas_materiales', 'cantidad'),
        ('entradas', 'cantidad')
      ) as columnas(tabla, columna)
  loop
    execute format(
      'select count(*) from public.%I where %I <> trunc(%I)',
      v_tabla, v_columna, v_columna
    ) into v_total;

    if v_total > 0 then
      raise exception
        'CANTIDADES_FRACCIONARIAS_EXISTENTES: public.%.% tiene % fila(s) con decimales. Corrige esos datos antes de aplicar esta migración.',
        v_tabla, v_columna, v_total;
    end if;
  end loop;
end $$;

-- Cantidad capturada: número de presentaciones completas.
alter table public.boletas_materiales
  add constraint boletas_materiales_cantidad_entera_ck
  check (cantidad = trunc(cantidad));

alter table public.entradas
  add constraint entradas_cantidad_entera_ck
  check (cantidad = trunc(cantidad));

-- La cantidad capturada debe ser entera, pero la conversión a unidad base
-- puede dar decimales. Ej.: 1 botella de 355 ml = 0.355 L.
create or replace function public.convertir_a_unidad_base(
  p_producto_id bigint, p_presentacion_id bigint, p_cantidad numeric)
returns numeric
language plpgsql stable security invoker set search_path = public as $$
declare
  v_factor numeric;
begin
  if p_cantidad is null or p_cantidad <= 0 then
    raise exception 'CANTIDAD_INVALIDA: La cantidad debe ser mayor a cero.';
  end if;
  if p_cantidad <> trunc(p_cantidad) then
    raise exception 'CANTIDAD_ENTERA_REQUERIDA: La cantidad debe ser un número entero.';
  end if;
  if p_presentacion_id is null then
    return p_cantidad;
  end if;
  select factor_a_base into v_factor from presentaciones_producto
   where id = p_presentacion_id and producto_id = p_producto_id and activo;
  if v_factor is null then
    raise exception 'PRESENTACION_INVALIDA: La presentación no corresponde al producto.';
  end if;
  -- Se conserva el redondeo a 3 decimales que ya usa la columna cantidad_base.
  return round(p_cantidad * v_factor, 3);
end $$;
